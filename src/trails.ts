import * as Cesium from 'cesium';

/**
 * Trail overlays for Offroad (4x4/OHV), Hiking, and MTB — the OnX-style layers.
 * Trails are sourced from OpenStreetMap (Overpass) for the current view and
 * drawn as ground-clamped polylines coloured by difficulty:
 *
 *   green  = easy        blue = intermediate
 *   black  = advanced    red  = expert / very difficult
 *   grey   = unrated (no difficulty tagged in OSM)
 *
 * Each layer is independent and refreshes as the camera settles, with results
 * cached per coarse view tile so panning doesn't hammer Overpass.
 */

export type TrailLayerId = 'offroad' | 'hiking' | 'mtb';

const ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
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

interface OverpassWay {
  type: string;
  tags?: Record<string, string>;
  geometry?: { lat: number; lon: number }[];
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
}

export class TrailLayers {
  private readonly layers: Record<TrailLayerId, LayerState>;
  private removeListener?: Cesium.Event.RemoveCallback;
  private debounce?: number;

  constructor(private readonly viewer: Cesium.Viewer) {
    const make = (id: string): LayerState => {
      const ds = new Cesium.CustomDataSource(id);
      void viewer.dataSources.add(ds);
      return { enabled: false, ds, cache: new Map(), lastKey: '', token: 0 };
    };
    this.layers = { offroad: make('offroad'), hiking: make('hiking'), mtb: make('mtb') };
  }

  setEnabled(id: TrailLayerId, on: boolean): void {
    const layer = this.layers[id];
    layer.enabled = on;
    if (!on) {
      layer.ds.entities.removeAll();
      layer.lastKey = '';
      this.viewer.scene.requestRender();
    }
    const anyOn = Object.values(this.layers).some((l) => l.enabled);
    if (anyOn && !this.removeListener) {
      this.viewer.camera.percentageChanged = 0.3;
      this.removeListener = this.viewer.camera.changed.addEventListener(() => this.schedule());
    } else if (!anyOn && this.removeListener) {
      this.removeListener();
      this.removeListener = undefined;
    }
    if (on) this.schedule(200);
  }

  isEnabled(id: TrailLayerId): boolean {
    return this.layers[id].enabled;
  }

  private schedule(delay = 550): void {
    window.clearTimeout(this.debounce);
    this.debounce = window.setTimeout(() => void this.refreshAll(), delay);
  }

  private altitude(): number {
    return Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC).height;
  }

  private async refreshAll(): Promise<void> {
    const rect = this.viewer.camera.computeViewRectangle(this.viewer.scene.globe.ellipsoid);
    const tooFar = this.altitude() > MAX_ALTITUDE;
    for (const id of Object.keys(this.layers) as TrailLayerId[]) {
      const layer = this.layers[id];
      if (!layer.enabled) continue;
      if (!rect || tooFar) {
        if (layer.ds.entities.values.length) layer.ds.entities.removeAll();
        layer.lastKey = '';
        continue;
      }
      const s = Cesium.Math.toDegrees(rect.south);
      const w = Cesium.Math.toDegrees(rect.west);
      const n = Cesium.Math.toDegrees(rect.north);
      const e = Cesium.Math.toDegrees(rect.east);
      if (n - s > MAX_SPAN_DEG || e - w > MAX_SPAN_DEG) continue;

      const key = `${s.toFixed(2)},${w.toFixed(2)},${n.toFixed(2)},${e.toFixed(2)}`;
      if (key === layer.lastKey) continue;
      layer.lastKey = key;

      const current = ++layer.token;
      let ways = layer.cache.get(key);
      if (!ways) {
        const fetched = await this.fetchTrails(id, s, w, n, e);
        if (current !== layer.token || !layer.enabled) return;
        if (!fetched) {
          layer.lastKey = '';
          continue;
        }
        ways = fetched;
        layer.cache.set(key, ways);
      }
      this.draw(layer, ways);
    }
    this.viewer.scene.requestRender();
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
    for (const el of data.elements) {
      if (el.type !== 'way' || !el.geometry || el.geometry.length < 2) continue;
      const coords: number[] = [];
      for (const p of el.geometry) coords.push(p.lon, p.lat);
      out.push({ coords, grade: grader(el.tags ?? {}) });
      if (out.length >= MAX_WAYS) break;
    }
    return out;
  }

  private draw(layer: LayerState, ways: TrailWay[]): void {
    layer.ds.entities.removeAll();
    for (const way of ways) {
      layer.ds.entities.add({
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray(way.coords),
          width: 4,
          clampToGround: true,
          classificationType: Cesium.ClassificationType.BOTH,
          material: DIFFICULTY[way.grade],
        },
      });
    }
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
  mtb: (b) =>
    [
      `way["mtb:scale"]${b}`,
      `way["mtb:scale:imba"]${b}`,
      `way["highway"="path"]["bicycle"~"designated|yes"]${b}`,
      `way["highway"="cycleway"]["surface"~"ground|dirt|earth|gravel|fine_gravel|unpaved"]${b}`,
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
    return 'unrated';
  },
  mtb: (t) => {
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
    return 'unrated';
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
    return 'unrated';
  },
};
