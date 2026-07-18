import * as Cesium from 'cesium';
import { overpassQuery } from './overpass';
import { requireCameraPercentageChanged, releaseCameraPercentageChanged } from './cameraThreshold';

/**
 * Trail overlays for Offroad (4x4/OHV), Hiking, and Bike — the OnX-style layers.
 * Trails are sourced from OpenStreetMap (Overpass) for the current view and
 * drawn coloured by difficulty:
 *
 *   green  = easy        blue = intermediate
 *   black  = advanced    red  = expert / very difficult
 *
 * Lines are draped onto the photoreal surface by sampling the actual tile
 * height at each vertex (the ellipsoid sits well below the 3D tiles, so plain
 * ground-clamping buries them). Each layer is independent and refreshes as the
 * camera settles, with results cached per coarse view tile so panning doesn't
 * hammer Overpass.
 */

export type TrailLayerId = 'offroad' | 'hiking' | 'bike';
export type TrailStatus = 'loading' | 'done' | 'empty' | 'error';

// Only fetch trails when reasonably close (metres of camera altitude).
const MAX_ALTITUDE = 22000;
const MAX_SPAN_DEG = 0.5;
const MAX_WAYS = 400;

const DIFFICULTY = {
  easy: Cesium.Color.fromCssColorString('#34C759'),
  intermediate: Cesium.Color.fromCssColorString('#0A84FF'),
  advanced: Cesium.Color.fromCssColorString('#111111'),
  expert: Cesium.Color.fromCssColorString('#FF3B30'),
  unrated: Cesium.Color.fromCssColorString('#8E8E93'),
} as const;

type Grade = keyof typeof DIFFICULTY;

interface OverpassGeom {
  lat: number;
  lon: number;
}

interface OverpassWay {
  type: string;
  tags?: Record<string, string>;
  geometry?: OverpassGeom[];
  members?: { type: string; role?: string; geometry?: OverpassGeom[] }[];
}

// Keep each way lightweight so height-sampling and rendering stay cheap.
const MAX_PTS_PER_WAY = 48;

// Cap each layer's per-view-tile cache so long panning sessions across many
// distinct view tiles don't grow it unbounded — same bounded-LRU idea as
// labelTexture.ts's canvas cache.
const MAX_CACHE_TILES = 60;

function downsampleCoords(coords: number[]): number[] {
  const n = coords.length / 2;
  if (n <= MAX_PTS_PER_WAY) return coords;
  const stride = Math.ceil(n / MAX_PTS_PER_WAY);
  const out: number[] = [];
  for (let i = 0; i < n; i += stride) out.push(coords[i * 2], coords[i * 2 + 1]);
  // Always keep the final vertex so the line reaches its true end.
  const lastLon = coords[(n - 1) * 2];
  const lastLat = coords[(n - 1) * 2 + 1];
  if (out[out.length - 2] !== lastLon || out[out.length - 1] !== lastLat) out.push(lastLon, lastLat);
  return out;
}

interface TrailWay {
  coords: number[]; // flat [lon, lat, lon, lat, …]
  grade: Grade;
}

interface LayerState {
  enabled: boolean;
  ds: Cesium.CustomDataSource;
  cache: Map<string, TrailWay[]>;
  lastKey: string;
  token: number;
  announce: boolean;
  debounce?: number;
  controller?: AbortController;
}

export class TrailLayers {
  private readonly layers: Record<TrailLayerId, LayerState>;
  private removeListener?: Cesium.Event.RemoveCallback;
  private statusHandler?: (id: TrailLayerId, status: TrailStatus, count: number) => void;

  constructor(private readonly viewer: Cesium.Viewer) {
    const make = (id: string): LayerState => {
      const ds = new Cesium.CustomDataSource(id);
      void viewer.dataSources.add(ds);
      return { enabled: false, ds, cache: new Map(), lastKey: '', token: 0, announce: false };
    };
    this.layers = { offroad: make('offroad'), hiking: make('hiking'), bike: make('bike') };
  }

  /** Report load state (loading/done/empty/error) after a user enables a layer. */
  onStatus(cb: (id: TrailLayerId, status: TrailStatus, count: number) => void): void {
    this.statusHandler = cb;
  }

  setEnabled(id: TrailLayerId, on: boolean): void {
    const layer = this.layers[id];
    layer.enabled = on;
    if (!on) {
      layer.controller?.abort();
      layer.ds.entities.removeAll();
      layer.lastKey = '';
      layer.announce = false;
      this.viewer.scene.requestRender();
    } else {
      layer.announce = true; // report the outcome of this first load to the user
    }
    const anyOn = Object.values(this.layers).some((l) => l.enabled);
    if (anyOn && !this.removeListener) {
      requireCameraPercentageChanged(this.viewer, 'trails', 0.3);
      this.removeListener = this.viewer.camera.changed.addEventListener(() => this.scheduleAll());
    } else if (!anyOn && this.removeListener) {
      this.removeListener();
      this.removeListener = undefined;
      releaseCameraPercentageChanged(this.viewer, 'trails');
    }
    if (on) this.schedule(id, 150);
  }

  isEnabled(id: TrailLayerId): boolean {
    return this.layers[id].enabled;
  }

  private scheduleAll(): void {
    for (const id of Object.keys(this.layers) as TrailLayerId[]) {
      if (this.layers[id].enabled) this.schedule(id);
    }
  }

  // Each layer refreshes on its own timer so several layers can load in parallel
  // without racing each other (which previously left some layers blank).
  private schedule(id: TrailLayerId, delay = 550): void {
    const layer = this.layers[id];
    window.clearTimeout(layer.debounce);
    layer.debounce = window.setTimeout(() => void this.refreshLayer(id), delay);
  }

  private altitude(): number {
    return Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC).height;
  }

  /**
   * Ground area to query, centred on the camera's own ground position (near the
   * user in a chase view), not the screen-centre pick (which shoots toward the
   * horizon in a tilted view) and not camera.computeViewRectangle() (null / a
   * huge rectangle when tilted — which silently prevented trails from loading).
   */
  private viewArea(): { s: number; w: number; n: number; e: number } | null {
    const carto = Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC);
    const lon = Cesium.Math.toDegrees(carto.longitude);
    const lat = Cesium.Math.toDegrees(carto.latitude);
    if (!isFinite(lon) || !isFinite(lat)) return null;
    const half = Math.min(Math.max((carto.height / 111000) * 0.9, 0.02), MAX_SPAN_DEG / 2);
    const cosLat = Math.max(Math.cos(Cesium.Math.toRadians(lat)), 0.2);
    return { s: lat - half, n: lat + half, w: lon - half / cosLat, e: lon + half / cosLat };
  }

  private async refreshLayer(id: TrailLayerId): Promise<void> {
    const layer = this.layers[id];
    if (!layer.enabled) return;

    const area = this.altitude() > MAX_ALTITUDE ? null : this.viewArea();
    if (!area) {
      if (layer.ds.entities.values.length) layer.ds.entities.removeAll();
      layer.lastKey = '';
      if (layer.announce) {
        layer.announce = false;
        this.statusHandler?.(id, 'empty', 0);
      }
      this.viewer.scene.requestRender();
      return;
    }
    const { s, w, n, e } = area;

    const key = `${s.toFixed(2)},${w.toFixed(2)},${n.toFixed(2)},${e.toFixed(2)}`;
    if (key === layer.lastKey) return;

    const current = ++layer.token;
    let ways = layer.cache.get(key);
    if (ways) {
      // Touch for simple oldest-eviction recency ordering (Map preserves insertion order).
      layer.cache.delete(key);
      layer.cache.set(key, ways);
    } else {
      if (layer.announce) this.statusHandler?.(id, 'loading', 0);
      // Cancel this layer's still-in-flight request for a now-stale view
      // before starting a new one — continuous panning would otherwise pile
      // up several concurrent Overpass queries whose results are all discarded.
      layer.controller?.abort();
      const controller = new AbortController();
      layer.controller = controller;
      const fetched = await this.fetchTrails(id, s, w, n, e, controller.signal);
      // A newer refresh for this layer superseded us, or it was turned off.
      if (current !== layer.token || !layer.enabled) return;
      if (!fetched) {
        // Leave lastKey unchanged so this view retries on the next settle.
        if (layer.announce) {
          layer.announce = false;
          this.statusHandler?.(id, 'error', 0);
        }
        return;
      }
      ways = fetched;
      layer.cache.set(key, ways);
      if (layer.cache.size > MAX_CACHE_TILES) {
        const oldestKey = layer.cache.keys().next().value;
        if (oldestKey !== undefined) layer.cache.delete(oldestKey);
      }
    }
    this.draw(layer, ways);
    // Only mark this view handled once it has actually been drawn.
    layer.lastKey = key;
    this.viewer.scene.requestRender();
    if (layer.announce) {
      layer.announce = false;
      this.statusHandler?.(id, ways.length ? 'done' : 'empty', ways.length);
    }
  }

  private async fetchTrails(
    id: TrailLayerId,
    s: number,
    w: number,
    n: number,
    e: number,
    signal: AbortSignal,
  ): Promise<TrailWay[] | null> {
    const bbox = `(${s},${w},${n},${e})`;
    const body = QUERY[id](bbox);
    // Every union member must end with ';' — including the last one before the
    // closing ')'. `.join(';')` omits the trailing one, which Overpass rejects
    // with a 400, so normalise it here.
    const inner = body.endsWith(';') ? body : `${body};`;
    const query = `[out:json][timeout:25];(${inner});out geom ${MAX_WAYS};`;
    const data = await overpassQuery<OverpassWay>(query, { signal });
    if (!data?.elements) return null;

    const grader = GRADERS[id];
    const out: TrailWay[] = [];
    const push = (geom: OverpassGeom[], tags: Record<string, string>): void => {
      if (!geom || geom.length < 2) return;
      const coords: number[] = [];
      for (const p of geom) coords.push(p.lon, p.lat);
      out.push({ coords: downsampleCoords(coords), grade: grader(tags) });
    };
    for (const el of data.elements) {
      if (out.length >= MAX_WAYS) break;
      if (el.type === 'way' && el.geometry) {
        push(el.geometry, el.tags ?? {});
      } else if (el.type === 'relation' && el.members) {
        // Signed cycle/route relations: draw each member way with the
        // relation's tags so the whole route shares one difficulty colour.
        for (const m of el.members) {
          if (out.length >= MAX_WAYS) break;
          if (m.type === 'way' && m.geometry) push(m.geometry, el.tags ?? {});
        }
      }
    }
    return out;
  }

  private draw(layer: LayerState, ways: TrailWay[]): void {
    layer.ds.entities.removeAll();
    // Drape lines directly onto the photoreal 3D tiles via GPU ground-clamping
    // (classify onto both terrain and 3D tiles). This tracks the real surface
    // every frame with no per-vertex height sampling, so it stays on the road
    // and doesn't bog the app down as the camera moves.
    const clamp = Cesium.GroundPolylinePrimitive.isSupported(this.viewer.scene);
    for (const way of ways) {
      const color = DIFFICULTY[way.grade];
      layer.ds.entities.add({
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray(way.coords),
          width: 5,
          // Solid colour with a white outline, matching the routes/location dot.
          material: new Cesium.PolylineOutlineMaterialProperty({
            color,
            outlineColor: Cesium.Color.WHITE,
            outlineWidth: 2,
          }),
          clampToGround: clamp,
          classificationType: clamp ? Cesium.ClassificationType.BOTH : undefined,
          // Fallback (unsupported GPU): show through terrain so it's still visible.
          depthFailMaterial: clamp ? undefined : new Cesium.ColorMaterialProperty(color.withAlpha(0.6)),
        },
      });
    }
    this.viewer.scene.requestRender();
  }
}

// ---------- Overpass query fragments per layer ----------

const QUERY: Record<TrailLayerId, (bbox: string) => string> = {
  hiking: (b) =>
    [
      `way["highway"="path"]${b}`,
      `way["highway"="footway"]["footway"!="sidewalk"]${b}`,
      `way["highway"="bridleway"]${b}`,
      `way["highway"="steps"]${b}`,
      `way["sac_scale"]${b}`,
    ].join(';'),
  bike: (b) =>
    [
      // Dedicated cycling infrastructure
      `way["highway"="cycleway"]${b}`,
      `way["bicycle"="designated"]${b}`,
      `way["cycleway"~"lane|track|shared_lane|opposite_lane"]${b}`,
      // Off-road / mountain-bike trails
      `way["mtb:scale"]${b}`,
      `way["mtb:scale:imba"]${b}`,
      `way["highway"~"path|track"]["bicycle"~"designated|yes"]${b}`,
      // Signed cycle routes (numbered/named networks) as relations
      `relation["route"="bicycle"]${b}`,
      `relation["route"="mtb"]${b}`,
    ].join(';'),
  offroad: (b) =>
    [
      `way["highway"="track"]${b}`,
      `way["4wd_only"="yes"]${b}`,
      `way["highway"="path"]["motor_vehicle"~"designated|yes"]${b}`,
    ].join(';'),
};

// ---------- Difficulty graders ----------

function leadingInt(v: string | undefined): number | null {
  if (v == null) return null;
  const m = v.match(/-?\d+/);
  return m ? parseInt(m[0], 10) : null;
}

const GRADERS: Record<TrailLayerId, (tags: Record<string, string>) => Grade> = {
  hiking: (t) => {
    switch (t.sac_scale) {
      case 'hiking':
        return 'easy';
      case 'mountain_hiking':
        return 'intermediate';
      case 'demanding_mountain_hiking':
        return 'advanced';
      case 'alpine_hiking':
      case 'demanding_alpine_hiking':
      case 'difficult_alpine_hiking':
        return 'expert';
    }
    // Steps / very poor visibility read as harder even without an SAC scale.
    if (t.highway === 'steps') return 'intermediate';
    if (t.trail_visibility === 'bad' || t.trail_visibility === 'horrible' || t.trail_visibility === 'no')
      return 'advanced';
    return 'easy';
  },
  bike: (t) => {
    const imba = leadingInt(t['mtb:scale:imba']);
    if (imba != null) {
      if (imba <= 1) return 'easy';
      if (imba === 2) return 'intermediate';
      if (imba === 3) return 'advanced';
      return 'expert';
    }
    const scale = leadingInt(t['mtb:scale']);
    if (scale != null) {
      if (scale <= 1) return 'easy';
      if (scale <= 3) return 'intermediate';
      if (scale === 4) return 'advanced';
      return 'expert';
    }
    // Regular cycleways / bike routes have no off-road difficulty — treat as easy.
    return 'easy';
  },
  offroad: (t) => {
    switch (t.tracktype) {
      case 'grade1':
        return 'easy';
      case 'grade2':
        return 'intermediate';
      case 'grade3':
        return 'advanced';
      case 'grade4':
      case 'grade5':
        return 'expert';
    }
    switch (t.smoothness) {
      case 'excellent':
      case 'good':
        return 'easy';
      case 'intermediate':
        return 'intermediate';
      case 'bad':
        return 'advanced';
      case 'very_bad':
      case 'horrible':
      case 'very_horrible':
      case 'impassable':
        return 'expert';
    }
    if (t['4wd_only'] === 'yes') return 'advanced';
    return 'easy';
  },
};
