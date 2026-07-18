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
// Cap the per-view-tile cache so long panning sessions across many distinct
// view tiles don't grow it unbounded (same bounded-LRU idea as trails.ts
// and labelTexture.ts's canvas cache).
const MAX_CACHE_TILES = 60;

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
  /**
   * Raw way geometry (roads only). Kept so `relayout()` can re-derive the
   * anchor point against the *live* camera position every tick, instead of
   * the anchor staying frozen at wherever the camera was when this ~1.1km
   * grid cell was first fetched — that staleness is what let labels drift
   * away from (and behind) the visible road as you travel through a cell.
   */
  geometry?: { lat: number; lon: number }[];
}

interface DrawnEntry {
  item: LabelItem;
  isRoad: boolean;
  /** CSS-pixel size, unrotated (for roads: the pre-rotation text size). */
  width: number;
  height: number;
  /**
   * Last known surface height (metres, ellipsoidal), explicitly baked into
   * the entity's position instead of relying on Cesium's automatic
   * `HeightReference` clamping — the same technique the GPS location dot and
   * drawn routes use (`scene.clampToHeight`/`clampToHeightMostDetailed`),
   * which sticks to the photoreal 3D tiles far more reliably.
   */
  surfaceHeight: number;
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
  private heightToken = 0;
  private heightInterval?: number;

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
      if (this.heightInterval === undefined) {
        // Batched, throttled height refresh for road labels sliding along
        // the road — decoupled from the (much more frequent) camera-changed
        // tick rate. `scene.clampToHeight` does an actual offscreen render +
        // readback per call, so calling it per-label on every relayout tick
        // (which can fire many times a second) was the source of a serious
        // slowdown; one batched clampToHeightMostDetailed call a few times a
        // second is dramatically cheaper and still keeps labels glued to the
        // surface closely enough that the lag isn't perceptible.
        this.heightInterval = window.setInterval(() => void this.refreshRoadHeights(), 700);
      }
      this.schedule(200);
    } else {
      this.removeListener?.();
      this.removeListener = undefined;
      releaseCameraPercentageChanged(this.viewer, 'streetLabels');
      window.clearInterval(this.heightInterval);
      this.heightInterval = undefined;
      this.controller?.abort();
      this.clearAll();
    }
  }

  /**
   * Batch-refresh the surface height of every currently-drawn road label in
   * one clampToHeightMostDetailed call, using whatever anchor position
   * `relayout()`'s cheap per-tick re-anchoring has most recently computed.
   */
  private async refreshRoadHeights(): Promise<void> {
    const snapshot = this.entries;
    const roads = snapshot.filter((e) => e.isRoad && e.billboard);
    if (roads.length === 0) return;
    const cartesians = roads.map((e) => Cesium.Cartesian3.fromDegrees(e.item.lon, e.item.lat, 0));
    let clamped: (Cesium.Cartesian3 | undefined)[];
    try {
      clamped = await this.viewer.scene.clampToHeightMostDetailed(cartesians);
    } catch {
      return;
    }
    if (this.entries !== snapshot) return; // a fetch rebuilt entries while we awaited
    let rendered = false;
    for (let i = 0; i < clamped.length; i++) {
      const c = clamped[i];
      if (!c) continue;
      const h = Cesium.Cartographic.fromCartesian(c).height;
      if (!isPlausibleHeight(h)) continue;
      const entry = roads[i];
      entry.surfaceHeight = h;
      if (entry.billboard) entry.billboard.position = Cesium.Cartesian3.fromDegrees(entry.item.lon, entry.item.lat, h);
      rendered = true;
    }
    if (rendered) this.viewer.scene.requestRender();
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
    if (items) {
      // Touch for simple oldest-eviction recency ordering (Map preserves insertion order).
      this.cache.delete(key);
      this.cache.set(key, items);
    } else {
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
      if (this.cache.size > MAX_CACHE_TILES) {
        const oldestKey = this.cache.keys().next().value;
        if (oldestKey !== undefined) this.cache.delete(oldestKey);
      }
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
        // Long highways can come back from Overpass with thousands of
        // vertices; downsample once here (both for the initial anchor pick
        // below and for the geometry stored for later per-tick re-anchoring)
        // so relayout()'s segment-projection scan stays cheap.
        const geometry = downsampleGeometry(el.geometry);
        // Anchor at the vertex closest to where the user actually is — NOT
        // the way's overall midpoint. Overpass's bbox filter selects whole
        // ways and returns their FULL geometry uncropped, so for a long road
        // the old "overall midpoint" anchor could sit far outside the
        // current view: the root cause of labels appearing to float away
        // from the visible road, or not appear at all.
        const { lon, lat, bearingDeg } = pickAnchorAndBearing(geometry, centerLon, centerLat);
        out.push({
          id: el.id,
          lon,
          lat,
          text: name,
          kind: 'road',
          bearingDeg,
          roadClass: roadClassOf(el.tags),
          geometry,
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
    const token = ++this.heightToken;
    const pending: { entry: DrawnEntry; lon: number; lat: number }[] = [];

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
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(200, 1, 3000, 0.75),
          translucencyByDistance: new Cesium.NearFarScalar(1800, 1, 3000, 0),
        });
        const entry: DrawnEntry = { item, isRoad: false, width, height, surfaceHeight: 0, flipped: false, label };
        this.entries.push(entry);
        pending.push({ entry, lon: item.lon, lat: item.lat });
      } else {
        const variant: LabelVariant = item.roadClass === 'major' ? 'roadMajor' : 'roadMinor';
        const { canvas, width, height } = getLabelCanvas(item.text, variant);
        const position = Cesium.Cartesian3.fromDegrees(item.lon, item.lat, 0);
        const billboard = this.roadBillboards.add({
          position,
          image: canvas,
          width,
          height,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          scaleByDistance: new Cesium.NearFarScalar(200, 1, 3000, 0.55),
          translucencyByDistance: new Cesium.NearFarScalar(1800, 1, 3000, 0),
          alignedAxis: tangentVector(position, item.bearingDeg),
        });
        const entry: DrawnEntry = { item, isRoad: true, width, height, surfaceHeight: 0, flipped: false, billboard };
        this.entries.push(entry);
        pending.push({ entry, lon: item.lon, lat: item.lat });
      }
    }

    // Sort once here (places, then major roads, then minor roads) rather
    // than re-sorting a cloned array on every `relayout()` tick.
    this.entries.sort((a, b) => priorityOf(a.item) - priorityOf(b.item));

    this.relayout();
    this.viewer.scene.requestRender();
    void this.refineInitialHeights(pending, token);
  }

  /**
   * Bake an explicit surface height into freshly-drawn labels, the same
   * batched `clampToHeightMostDetailed` technique already used for the GPS
   * location dot and drawn routes — Cesium's automatic `HeightReference`
   * clamping (the previous approach) proved unreliable against the
   * photoreal 3D tileset and is what let road names visibly float instead
   * of sticking to the surface. This is the one-off placement pass right
   * after a fetch; `relayout()`'s cheap synchronous clamp then keeps moving
   * road labels glued to the surface as their anchor slides along the road.
   */
  private async refineInitialHeights(
    pending: { entry: DrawnEntry; lon: number; lat: number }[],
    token: number,
  ): Promise<void> {
    if (pending.length === 0) return;
    const cartesians = pending.map((p) => Cesium.Cartesian3.fromDegrees(p.lon, p.lat, 0));
    let clamped: (Cesium.Cartesian3 | undefined)[];
    try {
      clamped = await this.viewer.scene.clampToHeightMostDetailed(cartesians);
    } catch {
      return;
    }
    if (token !== this.heightToken) return; // superseded by a newer fetch
    let rendered = false;
    for (let i = 0; i < clamped.length; i++) {
      const c = clamped[i];
      if (!c) continue;
      const h = Cesium.Cartographic.fromCartesian(c).height;
      if (!isPlausibleHeight(h)) continue;
      const { entry, lon, lat } = pending[i];
      entry.surfaceHeight = h;
      const pos = Cesium.Cartesian3.fromDegrees(lon, lat, h);
      if (entry.billboard) entry.billboard.position = pos;
      else if (entry.label) entry.label.position = pos;
      rendered = true;
    }
    if (rendered) this.viewer.scene.requestRender();
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
    const groundCarto = Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC);
    const camLon = Cesium.Math.toDegrees(groundCarto.longitude);
    const camLat = Cesium.Math.toDegrees(groundCarto.latitude);

    // `this.entries` is kept pre-sorted (places, then major roads, then
    // minor roads) by `draw()` — priority never changes over an entry's
    // lifetime, so cloning + re-sorting every tick was wasted work.
    const accepted: { x: number; y: number; radius: number }[] = [];
    let rendered = false;

    for (const entry of this.entries) {
      const primitive = entry.isRoad ? entry.billboard : entry.label;
      if (!primitive) continue;

      if (entry.billboard && entry.item.geometry) {
        // Re-anchor to the point on the road nearest the *live* camera
        // position every tick, rather than leaving it frozen at wherever the
        // camera was when this grid cell's Overpass fetch last ran.
        const { lon, lat, bearingDeg } = pickAnchorAndBearing(entry.item.geometry, camLon, camLat);
        entry.item.lon = lon;
        entry.item.lat = lat;
        entry.item.bearingDeg = bearingDeg;
        // Height itself is refreshed separately in a throttled batch
        // (`refreshRoadHeights`) rather than here — `scene.clampToHeight` is
        // an actual render+readback, and this position update runs on every
        // relayout tick, which can fire many times a second.
        entry.billboard.position = Cesium.Cartesian3.fromDegrees(lon, lat, entry.surfaceHeight);
      }

      if (entry.billboard) {
        const { axis, flipped } = roadAlignedAxis(
          scene,
          entry.billboard.position,
          entry.item.lon,
          entry.item.lat,
          entry.surfaceHeight,
          entry.item.bearingDeg,
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

/** A partly-loaded tile can return an absurd height; reject those (mirrors globe.ts's `plausibleHeight`). */
function isPlausibleHeight(h: number): boolean {
  return Number.isFinite(h) && h > -500 && h < 9000;
}

function metersBetween(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const cosLat = Math.max(Math.cos(Cesium.Math.toRadians((a.lat + b.lat) / 2)), 0.2);
  const dx = (b.lon - a.lon) * cosLat * METERS_PER_DEG_LAT;
  const dy = (b.lat - a.lat) * METERS_PER_DEG_LAT;
  return Math.hypot(dx, dy);
}

// Target spacing between kept vertices — comfortably denser than
// MIN_BEARING_SAMPLE_M (18m) so pickAnchorAndBearing's segment-projection
// and bearing-sampling accuracy (and the anti-floating/anti-upside-down
// fixes built on it) aren't affected by the downsampling.
const GEOMETRY_TARGET_SPACING_M = 20;
// Backstop point-count cap for pathological cases (extremely long way with
// very fine native spacing).
const MAX_GEOMETRY_POINTS = 200;

/**
 * Downsample a way's raw OSM geometry so relayout()'s per-tick
 * segment-projection scan (pickAnchorAndBearing) stays cheap even for
 * long highways that come back from Overpass with thousands of vertices.
 */
function downsampleGeometry(
  geometry: { lat: number; lon: number }[],
): { lat: number; lon: number }[] {
  if (geometry.length <= 2) return geometry;
  let totalLength = 0;
  for (let i = 0; i < geometry.length - 1; i++) totalLength += metersBetween(geometry[i], geometry[i + 1]);
  const avgSpacing = totalLength / (geometry.length - 1);
  if (avgSpacing >= GEOMETRY_TARGET_SPACING_M) return geometry; // already coarse enough

  let stride = Math.max(1, Math.round(GEOMETRY_TARGET_SPACING_M / avgSpacing));
  const minStrideForCap = Math.ceil(geometry.length / MAX_GEOMETRY_POINTS);
  stride = Math.max(stride, minStrideForCap);
  if (stride <= 1) return geometry;

  const out: { lat: number; lon: number }[] = [];
  for (let i = 0; i < geometry.length; i += stride) out.push(geometry[i]);
  const last = geometry[geometry.length - 1];
  if (out[out.length - 1] !== last) out.push(last);
  return out;
}

/**
 * Project the query center onto the nearest point ALONG the way's geometry
 * (not just the nearest vertex), and compute a bearing sampled over a short
 * walk in each direction so a single short/noisy OSM segment doesn't produce
 * a jittery bearing.
 *
 * Nearest-vertex anchoring (the previous approach) made the label hop
 * discretely between OSM's vertices — which for a long straight road are
 * often tens of metres apart — as the camera moved and `relayout()`
 * re-anchored every tick. That discrete hopping is what still read as
 * "floating"/jittery even after the anchor stopped freezing per grid-cell.
 * Projecting onto the segment instead gives a continuously-varying point,
 * so the label glides smoothly along the road.
 */
function pickAnchorAndBearing(
  geometry: { lat: number; lon: number }[],
  centerLon: number,
  centerLat: number,
): { lon: number; lat: number; bearingDeg: number } {
  if (geometry.length < 2) {
    const only = geometry[0] ?? { lat: centerLat, lon: centerLon };
    return { lon: only.lon, lat: only.lat, bearingDeg: 0 };
  }

  const kx = Math.max(Math.cos(Cesium.Math.toRadians(centerLat)), 0.2);
  const toXY = (p: { lat: number; lon: number }): [number, number] => [
    (p.lon - centerLon) * kx,
    p.lat - centerLat,
  ];

  let best = Infinity;
  let bestSeg = 0;
  let bestT = 0;
  for (let i = 0; i < geometry.length - 1; i++) {
    const [ax, ay] = toXY(geometry[i]);
    const [bx, by] = toXY(geometry[i + 1]);
    const abx = bx - ax;
    const aby = by - ay;
    const len2 = abx * abx + aby * aby || 1e-12;
    let t = -(ax * abx + ay * aby) / len2;
    t = Math.max(0, Math.min(1, t));
    const cx = ax + abx * t;
    const cy = ay + aby * t;
    const d2 = cx * cx + cy * cy;
    if (d2 < best) {
      best = d2;
      bestSeg = i;
      bestT = t;
    }
  }
  const segA = geometry[bestSeg];
  const segB = geometry[bestSeg + 1];
  const anchor = {
    lon: segA.lon + (segB.lon - segA.lon) * bestT,
    lat: segA.lat + (segB.lat - segA.lat) * bestT,
  };

  let behind = segA;
  let acc = metersBetween(anchor, segA);
  for (let i = bestSeg; i > 0 && acc < MIN_BEARING_SAMPLE_M; i--) {
    behind = geometry[i - 1];
    acc += metersBetween(geometry[i], geometry[i - 1]);
  }
  let ahead = segB;
  acc = metersBetween(anchor, segB);
  for (let i = bestSeg + 1; i < geometry.length - 1 && acc < MIN_BEARING_SAMPLE_M; i++) {
    ahead = geometry[i + 1];
    acc += metersBetween(geometry[i], geometry[i + 1]);
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

const BEARING_SAMPLE_DISTANCE_M = 10;
const FLIP_HYSTERESIS_DEG = 5;

/** A point `distanceM` metres from (lon, lat) along `bearingDeg` (standard spherical destination formula). */
function destinationPoint(
  lon: number,
  lat: number,
  bearingDeg: number,
  distanceM: number,
): { lon: number; lat: number } {
  const R = 6371000;
  const brng = Cesium.Math.toRadians(bearingDeg);
  const lat1 = Cesium.Math.toRadians(lat);
  const lon1 = Cesium.Math.toRadians(lon);
  const angDist = distanceM / R;
  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(angDist) + Math.cos(lat1) * Math.sin(angDist) * Math.cos(brng),
  );
  const lon2 =
    lon1 +
    Math.atan2(
      Math.sin(brng) * Math.sin(angDist) * Math.cos(lat1),
      Math.cos(angDist) - Math.sin(lat1) * Math.sin(lat2),
    );
  return { lon: Cesium.Math.toDegrees(lon2), lat: Cesium.Math.toDegrees(lat2) };
}

/**
 * A road's bearing is only known up to 180° (a line has no inherent
 * direction), so whichever way we pick, the text can end up upside-down from
 * some viewing angles as the camera orbits. The camera-heading-only
 * approximation this used to use ignored pitch/roll and got it wrong often
 * enough to visibly show upside-down names.
 *
 * The direct fix measures the actual screen-space reading direction: project
 * the anchor and a point a few metres ahead along the bearing, and look at
 * the full angle between them (not just whether "ahead" is above or below —
 * that alone only works for roads running roughly vertically on screen, and
 * was effectively a coin-flip for roads running roughly *horizontally*,
 * which is most of them in a typical view — exactly matching "some" street
 * names coming out upside-down). Flip 180° whenever that reading direction
 * points more than 90° away from "rightward" on screen, the same rule every
 * rotated-map-label implementation uses to keep text legible at any angle: a
 * horizontal-ish rotation reads normally, but past ±90° from pointing right
 * it would start reading backwards and upside-down. Hysteresis in degrees
 * (not raw pixels) avoids flicker right at that ±90° boundary regardless of
 * how far away the sampled "ahead" point projects.
 */
function roadAlignedAxis(
  scene: Cesium.Scene,
  position: Cesium.Cartesian3,
  lon: number,
  lat: number,
  surfaceHeight: number,
  bearingDeg: number,
  currentlyFlipped: boolean,
): { axis: Cesium.Cartesian3; flipped: boolean } {
  let flipped = currentlyFlipped;
  const anchorScreen = scene.cartesianToCanvasCoordinates(position);
  if (anchorScreen) {
    const ahead = destinationPoint(lon, lat, bearingDeg, BEARING_SAMPLE_DISTANCE_M);
    const aheadScreen = scene.cartesianToCanvasCoordinates(
      Cesium.Cartesian3.fromDegrees(ahead.lon, ahead.lat, surfaceHeight),
    );
    if (aheadScreen) {
      const dx = aheadScreen.x - anchorScreen.x;
      const dy = aheadScreen.y - anchorScreen.y;
      // Only bother if the two points didn't project to (near) the same
      // spot (e.g. looking straight down the road) — otherwise the angle is
      // meaningless noise and we just keep the last known flip state.
      if (Math.hypot(dx, dy) > 0.5) {
        const angleFromRight = Math.abs(Cesium.Math.toDegrees(Math.atan2(dy, dx)));
        if (!flipped && angleFromRight > 90 + FLIP_HYSTERESIS_DEG) flipped = true;
        else if (flipped && angleFromRight < 90 - FLIP_HYSTERESIS_DEG) flipped = false;
      }
    }
  }
  const finalBearing = flipped ? bearingDeg + 180 : bearingDeg;
  return { axis: tangentVector(position, finalBearing), flipped };
}
