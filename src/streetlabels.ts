import * as Cesium from 'cesium';
import { overpassQuery } from './overpass';
import { requireCameraPercentageChanged, releaseCameraPercentageChanged } from './cameraThreshold';
import { bearingDeg as computeBearing } from './geo';
import { getLabelCanvas, measureText, fontForVariant, type LabelVariant } from './labelTexture';

/**
 * Apple-Maps-style street name labels. Google Photorealistic 3D Tiles ship
 * without any text, so we overlay road (and a few place) names sourced from
 * OpenStreetMap via Overpass. Roads render as billboards rotated to the
 * road's local bearing (Cesium's text `Label` has no rotation at all — only
 * `Billboard` does, via `alignedAxis` — so road names are pre-rasterized to a
 * canvas and drawn as billboards); places stay as plain camera-facing labels,
 * matching Apple Maps (place names are never rotated there either). A
 * priority-based screen-space pass hides overlapping lower-priority labels,
 * since Cesium has no built-in decluttering.
 *
 * Three tiers of work, each with its own trigger/cost:
 *  - Tier A: screen-space projection of positioned/rotated labels — Cesium's
 *    own per-frame render, free (only happens when something changed, thanks
 *    to requestRenderMode).
 *  - Tier B (`relayout`): altitude fade, collision pass, rotation
 *    upright-flip — runs on every throttled `camera.changed` tick (cheap, ≤
 *    MAX_LABELS items), independent of whether new data was fetched, so
 *    panning within an already-cached area still re-lays-out correctly.
 *  - Tier C (`refresh`): Overpass refetch + anchor/bearing selection + canvas
 *    rasterization — the existing ~500ms debounce, cache-key gated.
 */

// Only show labels when the camera is near the ground (metres of altitude).
const MIN_ALTITUDE = 5;
const MAX_ALTITUDE = 8000;
// Labels fade out between these two altitudes instead of popping at the cutoff.
const FADE_START_ALTITUDE = 6000;
const MAX_SPAN_DEG = 0.45;
const MAX_LABELS = 70;

const METERS_PER_DEG_LAT = 111320;
// Walk at least this far in each direction from a road's anchor point before
// sampling its bearing, so one short/noisy OSM segment doesn't jitter it.
const MIN_BEARING_SAMPLE_M = 18;
const LABEL_MARGIN_PX = 4;

const MAJOR_HIGHWAY = new Set(['motorway', 'trunk', 'primary']);

interface OverpassWay {
  type: string;
  id?: number;
  tags?: Record<string, string>;
  geometry?: { lat: number; lon: number }[];
  lat?: number;
  lon?: number;
}

type RoadClass = 'major' | 'minor';

interface LabelItem {
  id: number;
  lon: number;
  lat: number;
  text: string;
  kind: 'road' | 'place';
  /** Compass bearing at the anchor point; unused (0) for places. */
  bearingDeg: number;
  roadClass?: RoadClass;
}

interface DrawnEntry {
  item: LabelItem;
  isRoad: boolean;
  /** CSS-pixel size, unrotated (for roads: the pre-rotation text size). */
  width: number;
  height: number;
  /** Current upright-flip state, for hysteresis in `relayout`. */
  flipped: boolean;
  label?: Cesium.Label;
  billboard?: Cesium.Billboard;
}

export class StreetLabels {
  private placeCollection: Cesium.LabelCollection;
  private roadBillboards: Cesium.BillboardCollection;
  private removeListener?: Cesium.Event.RemoveCallback;
  private enabled = true;
  private debounce?: number;
  private token = 0;
  private lastKey = '';
  private announce = false;
  private statusHandler?: (status: 'loading' | 'done' | 'empty' | 'error') => void;
  private readonly cache = new Map<string, LabelItem[]>();
  private controller?: AbortController;
  private entries: DrawnEntry[] = [];

  constructor(private readonly viewer: Cesium.Viewer) {
    // `scene` is REQUIRED for labels that clamp to the ground/terrain — without
    // it, Cesium throws "undefined is not an object (a.globe)" the moment a
    // clamped label is drawn.
    this.placeCollection = viewer.scene.primitives.add(
      new Cesium.LabelCollection({ scene: viewer.scene }),
    );
    this.roadBillboards = viewer.scene.primitives.add(
      new Cesium.BillboardCollection({ scene: viewer.scene }),
    );
  }

  /** Report load state (loading/done/empty/error) after the user enables labels. */
  onStatus(cb: (status: 'loading' | 'done' | 'empty' | 'error') => void): void {
    this.statusHandler = cb;
  }

  setEnabled(on: boolean): void {
    this.enabled = on;
    if (on) {
      this.announce = true; // surface the outcome of this (re)enable to the user
      if (!this.removeListener) {
        this.removeListener = this.viewer.camera.changed.addEventListener(() => {
          // Cheap layout pass every tick, independent of the debounced fetch —
          // otherwise panning within an already-cached area never re-lays-out.
          this.relayout();
          this.schedule();
        });
        requireCameraPercentageChanged(this.viewer, 'streetLabels', 0.25);
      }
      this.schedule(200);
    } else {
      this.removeListener?.();
      this.removeListener = undefined;
      releaseCameraPercentageChanged(this.viewer, 'streetLabels');
      this.controller?.abort();
      this.clearAll();
    }
  }

  private clearAll(): void {
    this.placeCollection.removeAll();
    this.roadBillboards.removeAll();
    this.entries = [];
    this.viewer.scene.requestRender();
  }

  private schedule(delay = 500): void {
    if (!this.enabled) return;
    window.clearTimeout(this.debounce);
    this.debounce = window.setTimeout(() => void this.refresh(), delay);
  }

  private altitude(): number {
    return Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC).height;
  }

  /**
   * The ground area to label, centred on the camera's own ground position
   * (the point directly below the camera). We deliberately do NOT centre on the
   * screen-centre pick: in a tilted chase view the crosshair shoots toward the
   * horizon, so labels would load tens of km ahead of the user instead of
   * around them. And we don't use camera.computeViewRectangle() — in a tilted
   * view it returns null / a huge rectangle, which made labels never load.
   */
  private viewArea(): { s: number; w: number; n: number; e: number; centerLon: number; centerLat: number } | null {
    const carto = Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC);
    const lon = Cesium.Math.toDegrees(carto.longitude);
    const lat = Cesium.Math.toDegrees(carto.latitude);
    if (!isFinite(lon) || !isFinite(lat)) return null;
    // Span grows with altitude but is floored so we always cover a readable
    // neighbourhood (~4 km), and capped so we never over-fetch.
    const half = Math.min(Math.max((carto.height / 111000) * 0.9, 0.02), MAX_SPAN_DEG / 2);
    const cosLat = Math.max(Math.cos(Cesium.Math.toRadians(lat)), 0.2);
    return {
      s: lat - half,
      n: lat + half,
      w: lon - half / cosLat,
      e: lon + half / cosLat,
      centerLon: lon,
      centerLat: lat,
    };
  }

  private async refresh(): Promise<void> {
    if (!this.enabled) return;
    const alt = this.altitude();
    if (alt < MIN_ALTITUDE || alt > MAX_ALTITUDE) {
      // By the time altitude reaches MAX_ALTITUDE, relayout()'s fade has
      // already ramped visible labels to 0 alpha, so this clear is invisible.
      if (this.entries.length) this.clearAll();
      this.lastKey = '';
      return;
    }
    const area = this.viewArea();
    if (!area) return;
    const { s, w, n, e, centerLon, centerLat } = area;

    const key = `${s.toFixed(2)},${w.toFixed(2)},${n.toFixed(2)},${e.toFixed(2)}`;
    if (key === this.lastKey) return;

    const current = ++this.token;
    let items = this.cache.get(key);
    if (!items) {
      if (this.announce) this.statusHandler?.('loading');
      // Cancel a still-in-flight request for a now-stale view before starting
      // this one — otherwise continuous panning can pile up several
      // concurrent Overpass queries whose results all get thrown away anyway.
      this.controller?.abort();
      const controller = new AbortController();
      this.controller = controller;
      const fetched = await this.fetchLabels(s, w, n, e, centerLon, centerLat, controller.signal);
      // Superseded by a newer refresh, or labels were turned off (which aborts
      // this fetch) while we were waiting — either way, not a real error.
      if (current !== this.token || !this.enabled) return;
      if (!fetched) {
        // Leave lastKey unchanged so this view retries on the next settle.
        if (this.announce) {
          this.announce = false;
          this.statusHandler?.('error');
        }
        return;
      }
      items = fetched;
      this.cache.set(key, items);
    }
    this.draw(items);
    // Only mark this view handled once it has actually been drawn.
    this.lastKey = key;
    if (this.announce) {
      this.announce = false;
      this.statusHandler?.(items.length ? 'done' : 'empty');
    }
  }

  private async fetchLabels(
    s: number,
    w: number,
    n: number,
    e: number,
    centerLon: number,
    centerLat: number,
    signal: AbortSignal,
  ): Promise<LabelItem[] | null> {
    const bbox = `${s},${w},${n},${e}`;
    const query =
      `[out:json][timeout:20];(` +
      `way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|pedestrian)$"]["name"](${bbox});` +
      `node["place"~"^(city|town|village|suburb|neighbourhood)$"]["name"](${bbox});` +
      `);out geom ${MAX_LABELS * 4};`;
    const data = await overpassQuery<OverpassWay>(query, { signal });
    if (!data?.elements) return null;

    const out: LabelItem[] = [];
    const seen = new Set<number>();
    for (const el of data.elements) {
      const name = el.tags?.name;
      if (!name || el.id == null || seen.has(el.id)) continue;

      if (el.type === 'node' && el.lat != null && el.lon != null) {
        seen.add(el.id);
        out.push({ id: el.id, lon: el.lon, lat: el.lat, text: name, kind: 'place', bearingDeg: 0 });
      } else if (el.type === 'way' && el.geometry?.length) {
        seen.add(el.id);
        // Anchor at the vertex closest to where the user actually is — NOT
        // the way's overall midpoint. Overpass's bbox filter selects whole
        // ways and returns their FULL geometry uncropped, so for a long road
        // the old "overall midpoint" anchor could sit far outside the
        // current view: the root cause of labels appearing to float away
        // from the visible road, or not appear at all.
        const { lon, lat, bearingDeg } = pickAnchorAndBearing(el.geometry, centerLon, centerLat);
        out.push({
          id: el.id,
          lon,
          lat,
          text: name,
          kind: 'road',
          bearingDeg,
          roadClass: roadClassOf(el.tags),
        });
      }
    }
    // Places first (bigger), then roads; cap the total.
    out.sort((a, b) => (a.kind === b.kind ? 0 : a.kind === 'place' ? -1 : 1));
    return out.slice(0, MAX_LABELS);
  }

  private draw(items: LabelItem[]): void {
    this.placeCollection.removeAll();
    this.roadBillboards.removeAll();
    this.entries = [];

    for (const item of items) {
      if (item.kind === 'place') {
        const font = fontForVariant('place');
        const { width, height } = measureText(item.text, font);
        const label = this.placeCollection.add({
          position: Cesium.Cartesian3.fromDegrees(item.lon, item.lat, 0),
          text: item.text,
          font,
          fillColor: Cesium.Color.WHITE,
          outlineColor: new Cesium.Color(0, 0, 0, 0.85),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          // Clamp directly to the photoreal 3D tiles so names sit on the road.
          // CLAMP_TO_GROUND would snap to the ellipsoid (sea level), which is
          // far below the tiles, burying the labels; CLAMP_TO_3D_TILE tracks
          // the real surface every frame with no manual height sampling.
          heightReference: Cesium.HeightReference.CLAMP_TO_3D_TILE,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(200, 1, 3000, 0.75),
          translucencyByDistance: new Cesium.NearFarScalar(1800, 1, 3000, 0),
        });
        this.entries.push({ item, isRoad: false, width, height, flipped: false, label });
      } else {
        const variant: LabelVariant = item.roadClass === 'major' ? 'roadMajor' : 'roadMinor';
        const { canvas, width, height } = getLabelCanvas(item.text, variant);
        const position = Cesium.Cartesian3.fromDegrees(item.lon, item.lat, 0);
        const billboard = this.roadBillboards.add({
          position,
          image: canvas,
          width,
          height,
          heightReference: Cesium.HeightReference.CLAMP_TO_3D_TILE,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          scaleByDistance: new Cesium.NearFarScalar(200, 1, 3000, 0.55),
          translucencyByDistance: new Cesium.NearFarScalar(1800, 1, 3000, 0),
          alignedAxis: tangentVector(position, item.bearingDeg),
        });
        this.entries.push({ item, isRoad: true, width, height, flipped: false, billboard });
      }
    }

    this.relayout();
    this.viewer.scene.requestRender();
  }

  /**
   * Tier B: re-run on every throttled camera-changed tick, independent of
   * whether new data was fetched. Applies the altitude fade, keeps rotated
   * road labels upright as the camera orbits, and hides lower-priority
   * labels that would overlap an already-placed higher-priority one (Cesium
   * has no built-in decluttering, so this is hand-rolled).
   */
  private relayout(): void {
    if (this.entries.length === 0) return;
    const scene = this.viewer.scene;
    const altFade = altitudeFade(this.altitude());
    const headingDeg = Cesium.Math.toDegrees(this.viewer.camera.heading);

    // Places first, then major roads, then minor roads.
    const sorted = [...this.entries].sort((a, b) => priorityOf(a.item) - priorityOf(b.item));
    const accepted: { x: number; y: number; radius: number }[] = [];
    let rendered = false;

    for (const entry of sorted) {
      const primitive = entry.isRoad ? entry.billboard : entry.label;
      if (!primitive) continue;

      if (entry.billboard) {
        const { axis, flipped } = roadAlignedAxis(
          entry.billboard.position,
          entry.item.bearingDeg,
          headingDeg,
          entry.flipped,
        );
        entry.flipped = flipped;
        entry.billboard.alignedAxis = axis;
        entry.billboard.color = Cesium.Color.WHITE.withAlpha(altFade);
      } else if (entry.label) {
        entry.label.fillColor = Cesium.Color.WHITE.withAlpha(altFade);
        entry.label.outlineColor = new Cesium.Color(0, 0, 0, 0.85 * altFade);
      }

      if (altFade <= 0) {
        if (primitive.show) rendered = true;
        primitive.show = false;
        continue;
      }

      const screen = primitive.computeScreenSpacePosition(scene);
      if (!screen) {
        primitive.show = false;
        continue;
      }
      // Rotated road text has no simple screen-space angle available (Cesium
      // computes alignedAxis rotation internally), so its footprint is
      // approximated as a circle from the canvas diagonal — conservative
      // (slightly over-hides) rather than under-hides, which is the safer
      // direction given there's no Cesium-native decluttering to lean on.
      const radius = Math.hypot(entry.width, entry.height) / 2 + LABEL_MARGIN_PX;
      const overlaps = accepted.some(
        (b) => Math.hypot(screen.x - b.x, screen.y - b.y) < radius + b.radius,
      );
      if (overlaps) {
        primitive.show = false;
        continue;
      }
      primitive.show = true;
      rendered = true;
      accepted.push({ x: screen.x, y: screen.y, radius });
    }

    if (rendered) this.viewer.scene.requestRender();
  }
}

// ---------- module-level helpers ----------

function roadClassOf(tags: Record<string, string> | undefined): RoadClass {
  return tags?.highway && MAJOR_HIGHWAY.has(tags.highway) ? 'major' : 'minor';
}

function priorityOf(item: LabelItem): number {
  if (item.kind === 'place') return 0;
  return item.roadClass === 'major' ? 1 : 2;
}

function metersBetween(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const cosLat = Math.max(Math.cos(Cesium.Math.toRadians((a.lat + b.lat) / 2)), 0.2);
  const dx = (b.lon - a.lon) * cosLat * METERS_PER_DEG_LAT;
  const dy = (b.lat - a.lat) * METERS_PER_DEG_LAT;
  return Math.hypot(dx, dy);
}

/**
 * Pick the point in a way's geometry closest to the query center, and
 * compute a bearing sampled over a short walk in each direction so a single
 * short/noisy OSM segment doesn't produce a jittery bearing.
 */
function pickAnchorAndBearing(
  geometry: { lat: number; lon: number }[],
  centerLon: number,
  centerLat: number,
): { lon: number; lat: number; bearingDeg: number } {
  let bestIdx = 0;
  let bestDist = Infinity;
  for (let i = 0; i < geometry.length; i++) {
    const d = metersBetween(geometry[i], { lat: centerLat, lon: centerLon });
    if (d < bestDist) {
      bestDist = d;
      bestIdx = i;
    }
  }
  const anchor = geometry[bestIdx];

  let behind = anchor;
  let acc = 0;
  for (let i = bestIdx; i > 0 && acc < MIN_BEARING_SAMPLE_M; i--) {
    acc += metersBetween(geometry[i], geometry[i - 1]);
    behind = geometry[i - 1];
  }
  let ahead = anchor;
  acc = 0;
  for (let i = bestIdx; i < geometry.length - 1 && acc < MIN_BEARING_SAMPLE_M; i++) {
    acc += metersBetween(geometry[i], geometry[i + 1]);
    ahead = geometry[i + 1];
  }
  const bearingDeg =
    behind.lon === ahead.lon && behind.lat === ahead.lat
      ? 0
      : computeBearing([behind.lon, behind.lat], [ahead.lon, ahead.lat]);

  return { lon: anchor.lon, lat: anchor.lat, bearingDeg };
}

function altitudeFade(alt: number): number {
  if (alt <= FADE_START_ALTITUDE) return 1;
  if (alt >= MAX_ALTITUDE) return 0;
  return 1 - (alt - FADE_START_ALTITUDE) / (MAX_ALTITUDE - FADE_START_ALTITUDE);
}

/** World-space unit vector for a compass bearing at a surface position, for `Billboard.alignedAxis`. */
function tangentVector(position: Cesium.Cartesian3, bearingDeg: number): Cesium.Cartesian3 {
  const frame = Cesium.Transforms.eastNorthUpToFixedFrame(position);
  const rad = Cesium.Math.toRadians(bearingDeg);
  const local = new Cesium.Cartesian3(Math.sin(rad), Math.cos(rad), 0);
  const world = new Cesium.Cartesian3();
  Cesium.Matrix4.multiplyByPointAsVector(frame, local, world);
  return Cesium.Cartesian3.normalize(world, world);
}

function normalizeAngleDeg(deg: number): number {
  let d = deg % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/**
 * A road's bearing is only known up to 180° (a line has no inherent
 * direction), so whichever way we pick, the text can end up upside-down from
 * some viewing angles as the camera orbits. Flip 180° when the bearing points
 * more than ~90° away from the camera's current heading, with a hysteresis
 * band (80°-100°) so it doesn't flip back and forth right at the boundary.
 * This is a heading-only approximation (doesn't account for camera pitch),
 * matching the scope agreed for this pass — a closer-to-exact fix would need
 * a full screen-space projection check.
 */
function roadAlignedAxis(
  position: Cesium.Cartesian3,
  bearingDeg: number,
  cameraHeadingDeg: number,
  currentlyFlipped: boolean,
): { axis: Cesium.Cartesian3; flipped: boolean } {
  const diff = normalizeAngleDeg(bearingDeg - cameraHeadingDeg);
  const threshold = currentlyFlipped ? 80 : 100;
  const flipped = Math.abs(diff) > threshold;
  const finalBearing = flipped ? bearingDeg + 180 : bearingDeg;
  return { axis: tangentVector(position, finalBearing), flipped };
}
