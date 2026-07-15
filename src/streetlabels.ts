import * as Cesium from 'cesium';

/**
 * Apple-Maps-style street name labels. Google Photorealistic 3D Tiles ship
 * without any text, so we overlay road (and a few place) names sourced from
 * OpenStreetMap via Overpass, placed along the roads and floating over the 3D
 * scene. Labels refresh as the camera settles at street level and are cached
 * per coarse view tile so panning around doesn't hammer Overpass.
 */

const ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

// Only show labels when the camera is near the ground (metres of altitude).
const MIN_ALTITUDE = 40;
const MAX_ALTITUDE = 2600;
const MAX_LABELS = 60;

interface OverpassWay {
  type: string;
  tags?: Record<string, string>;
  geometry?: { lat: number; lon: number }[];
  lat?: number;
  lon?: number;
}

export class StreetLabels {
  private collection: Cesium.LabelCollection;
  private removeListener?: Cesium.Event.RemoveCallback;
  private enabled = true;
  private debounce?: number;
  private token = 0;
  private lastKey = '';
  private readonly cache = new Map<string, { lon: number; lat: number; text: string; kind: 'road' | 'place' }[]>();

  constructor(private readonly viewer: Cesium.Viewer) {
    this.collection = viewer.scene.primitives.add(new Cesium.LabelCollection());
  }

  setEnabled(on: boolean): void {
    this.enabled = on;
    if (on) {
      if (!this.removeListener) {
        this.removeListener = this.viewer.camera.changed.addEventListener(() => this.schedule());
        this.viewer.camera.percentageChanged = 0.25;
      }
      this.schedule(200);
    } else {
      this.removeListener?.();
      this.removeListener = undefined;
      this.collection.removeAll();
      this.viewer.scene.requestRender();
    }
  }

  private schedule(delay = 500): void {
    if (!this.enabled) return;
    window.clearTimeout(this.debounce);
    this.debounce = window.setTimeout(() => void this.refresh(), delay);
  }

  private altitude(): number {
    return Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC).height;
  }

  private viewRect(): Cesium.Rectangle | null {
    return this.viewer.camera.computeViewRectangle(this.viewer.scene.globe.ellipsoid) ?? null;
  }

  private async refresh(): Promise<void> {
    if (!this.enabled) return;
    const alt = this.altitude();
    if (alt < MIN_ALTITUDE || alt > MAX_ALTITUDE) {
      if (this.collection.length) {
        this.collection.removeAll();
        this.viewer.scene.requestRender();
      }
      this.lastKey = '';
      return;
    }
    const rect = this.viewRect();
    if (!rect) return;

    const s = Cesium.Math.toDegrees(rect.south);
    const w = Cesium.Math.toDegrees(rect.west);
    const n = Cesium.Math.toDegrees(rect.north);
    const e = Cesium.Math.toDegrees(rect.east);
    // Guard against huge (whole-globe) rectangles.
    if (n - s > 0.25 || e - w > 0.25) return;

    const key = `${s.toFixed(2)},${w.toFixed(2)},${n.toFixed(2)},${e.toFixed(2)}`;
    if (key === this.lastKey) return;
    this.lastKey = key;

    const current = ++this.token;
    let items = this.cache.get(key);
    if (!items) {
      const fetched = await this.fetchLabels(s, w, n, e);
      if (current !== this.token) return;
      if (!fetched) return;
      items = fetched;
      this.cache.set(key, items);
    }
    this.draw(items);
  }

  private async fetchLabels(
    s: number,
    w: number,
    n: number,
    e: number,
  ): Promise<{ lon: number; lat: number; text: string; kind: 'road' | 'place' }[] | null> {
    const bbox = `${s},${w},${n},${e}`;
    const query =
      `[out:json][timeout:20];(` +
      `way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|pedestrian)$"]["name"](${bbox});` +
      `node["place"~"^(city|town|village|suburb|neighbourhood)$"]["name"](${bbox});` +
      `);out geom ${MAX_LABELS * 4};`;
    let data: { elements?: OverpassWay[] } | null = null;
    for (const endpoint of ENDPOINTS) {
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 12000);
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
        /* try the next mirror */
      }
    }
    if (!data?.elements) return null;

    const out: { lon: number; lat: number; text: string; kind: 'road' | 'place' }[] = [];
    const seen = new Set<string>();
    for (const el of data.elements) {
      const name = el.tags?.name;
      if (!name) continue;
      if (el.type === 'node' && el.lat != null && el.lon != null) {
        const key = `p:${name}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ lon: el.lon, lat: el.lat, text: name, kind: 'place' });
      } else if (el.type === 'way' && el.geometry?.length) {
        // De-dupe repeated road names; place the label near the road's middle.
        if (seen.has(name)) continue;
        seen.add(name);
        const mid = el.geometry[Math.floor(el.geometry.length / 2)];
        out.push({ lon: mid.lon, lat: mid.lat, text: name, kind: 'road' });
      }
    }
    // Places first (bigger), then roads; cap the total.
    out.sort((a, b) => (a.kind === b.kind ? 0 : a.kind === 'place' ? -1 : 1));
    return out.slice(0, MAX_LABELS);
  }

  private draw(items: { lon: number; lat: number; text: string; kind: 'road' | 'place' }[]): void {
    this.collection.removeAll();
    for (const it of items) {
      const place = it.kind === 'place';
      this.collection.add({
        position: Cesium.Cartesian3.fromDegrees(it.lon, it.lat, 0),
        text: it.text,
        font: place
          ? '600 15px -apple-system, BlinkMacSystemFont, system-ui, sans-serif'
          : '500 12px -apple-system, BlinkMacSystemFont, system-ui, sans-serif',
        fillColor: place ? Cesium.Color.WHITE : Cesium.Color.fromCssColorString('#eef1f6'),
        outlineColor: new Cesium.Color(0, 0, 0, 0.85),
        outlineWidth: 3,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: new Cesium.NearFarScalar(200, 1, 3000, place ? 0.75 : 0.55),
        translucencyByDistance: new Cesium.NearFarScalar(1800, 1, 3000, 0),
        pixelOffset: place ? new Cesium.Cartesian2(0, 0) : new Cesium.Cartesian2(0, 0),
      });
    }
    this.viewer.scene.requestRender();
  }
}
