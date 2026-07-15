import * as Cesium from 'cesium';

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

const ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

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
      layer.ds.entities.removeAll();
      layer.lastKey = '';
      layer.announce = false;
      this.viewer.scene.requestRender();
    } else {
      layer.announce = true; // report the outcome of this first load to the user
    }
    const anyOn = Object.values(this.layers).some((l) => l.enabled);
    if (anyOn && !this.removeListener) {
      this.viewer.camera.percentageChanged = 0.3;
      this.removeListener = this.viewer.camera.changed.addEventListener(() => this.scheduleAll());
    } else if (!anyOn && this.removeListener) {
      this.removeListener();
      this.removeListener = undefined;
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

  private async refreshLayer(id: TrailLayerId): Promise<void> {
    const layer = this.layers[id];
    if (!layer.enabled) return;

    const rect = this.viewer.camera.computeViewRectangle(this.viewer.scene.globe.ellipsoid);
    if (!rect || this.altitude() > MAX_ALTITUDE) {
      if (layer.ds.entities.values.length) layer.ds.entities.removeAll();
      layer.lastKey = '';
      if (layer.announce) {
        layer.announce = false;
        this.statusHandler?.(id, 'empty', 0);
      }
      this.viewer.scene.requestRender();
      return;
    }
    const s = Cesium.Math.toDegrees(rect.south);
    const w = Cesium.Math.toDegrees(rect.west);
    const n = Cesium.Math.toDegrees(rect.north);
    const e = Cesium.Math.toDegrees(rect.east);
    if (n - s > MAX_SPAN_DEG || e - w > MAX_SPAN_DEG) return;

    const key = `${s.toFixed(2)},${w.toFixed(2)},${n.toFixed(2)},${e.toFixed(2)}`;
    if (key === layer.lastKey) return;
    layer.lastKey = key;

    const current = ++layer.token;
    let ways = layer.cache.get(key);
    if (!ways) {
      if (layer.announce) this.statusHandler?.(id, 'loading', 0);
      const fetched = await this.fetchTrails(id, s, w, n, e);
      // A newer refresh for this layer superseded us, or it was turned off.
      if (current !== layer.token || !layer.enabled) return;
      if (!fetched) {
        layer.lastKey = '';
        if (layer.announce) {
          layer.announce = false;
          this.statusHandler?.(id, 'error', 0);
        }
        return;
      }
      ways = fetched;
      layer.cache.set(key, ways);
    }
    this.draw(layer, ways);
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
  ): Promise<TrailWay[] | null> {
    const bbox = `(${s},${w},${n},${e})`;
    const body = QUERY[id](bbox);
    const query = `[out:json][timeout:25];(${body});out geom ${MAX_WAYS};`;
    let data: { elements?: OverpassWay[] } | null = null;
    for (const endpoint of ENDPOINTS) {
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 15000);
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: `data=${encodeURIComponent(query)}`,
          signal: controller.signal,
        });
        clearTimeout(timer);
        if (!res.ok) continue;
        data = await res.json();
        break;
      } catch {
        /* try next mirror */
      }
    }
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
    const gen = layer.token;
    const entries: { entity: Cesium.Entity; coords: number[] }[] = [];
    for (const way of ways) {
      const color = DIFFICULTY[way.grade];
      const entity = layer.ds.entities.add({
        polyline: {
          // Start slightly above the ellipsoid; corrected to the true surface
          // height once sampling completes (see clampToSurface).
          positions: Cesium.Cartesian3.fromDegreesArray(way.coords),
          width: 5,
          material: color,
          // Draw a faint version through the terrain so the trail stays legible
          // even where the 3D buildings/hills would otherwise occlude it.
          depthFailMaterial: new Cesium.ColorMaterialProperty(color.withAlpha(0.55)),
        },
      });
      entries.push({ entity, coords: way.coords });
    }
    this.viewer.scene.requestRender();
    void this.clampToSurface(layer, gen, entries);
  }

  /**
   * Drape trail lines onto the photoreal 3D tiles by sampling the real surface
   * height at every vertex in one batch, then repositioning each polyline.
   */
  private async clampToSurface(
    layer: LayerState,
    gen: number,
    entries: { entity: Cesium.Entity; coords: number[] }[],
  ): Promise<void> {
    const flat: Cesium.Cartesian3[] = [];
    const counts: number[] = [];
    for (const e of entries) {
      const n = e.coords.length / 2;
      counts.push(n);
      for (let i = 0; i < n; i++) {
        flat.push(Cesium.Cartesian3.fromDegrees(e.coords[i * 2], e.coords[i * 2 + 1], 0));
      }
    }
    if (flat.length === 0) return;
    let clamped: (Cesium.Cartesian3 | undefined)[];
    try {
      clamped = await this.viewer.scene.clampToHeightMostDetailed(flat);
    } catch {
      return;
    }
    // Bail out if this layer was refreshed/disabled while we were sampling.
    if (gen !== layer.token || !layer.enabled) return;
    let k = 0;
    for (let ei = 0; ei < entries.length; ei++) {
      const e = entries[ei];
      const positions: Cesium.Cartesian3[] = [];
      for (let i = 0; i < counts[ei]; i++) {
        const c = clamped[k++];
        const lon = e.coords[i * 2];
        const lat = e.coords[i * 2 + 1];
        let h = 0;
        if (c) {
          const hh = Cesium.Cartographic.fromCartesian(c).height;
          if (isFinite(hh)) h = hh;
        }
        positions.push(Cesium.Cartesian3.fromDegrees(lon, lat, h + 1.5));
      }
      if (e.entity.polyline) e.entity.polyline.positions = new Cesium.ConstantProperty(positions);
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
