import * as Cesium from 'cesium';
import { overpassQuery } from './overpass';
import { requireCameraPercentageChanged, releaseCameraPercentageChanged } from './cameraThreshold';

/**
 * Apple-Maps-style street name labels. Google Photorealistic 3D Tiles ship
 * without any text, so we overlay road (and a few place) names sourced from
 * OpenStreetMap via Overpass, placed along the roads and floating over the 3D
 * scene. Labels refresh as the camera settles at street level and are cached
 * per coarse view tile so panning around doesn't hammer Overpass.
 */

// Only show labels when the camera is near the ground (metres of altitude).
const MIN_ALTITUDE = 5;
const MAX_ALTITUDE = 8000;
const MAX_SPAN_DEG = 0.45;
const MAX_LABELS = 70;

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
  private announce = false;
  private statusHandler?: (status: 'loading' | 'done' | 'empty' | 'error') => void;
  private readonly cache = new Map<string, { lon: number; lat: number; text: string; kind: 'road' | 'place' }[]>();
  private controller?: AbortController;

  constructor(private readonly viewer: Cesium.Viewer) {
    // `scene` is REQUIRED for labels that clamp to the ground/terrain — without
    // it, Cesium throws "undefined is not an object (a.globe)" the moment a
    // clamped label is drawn.
    this.collection = viewer.scene.primitives.add(
      new Cesium.LabelCollection({ scene: viewer.scene }),
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
        this.removeListener = this.viewer.camera.changed.addEventListener(() => this.schedule());
        requireCameraPercentageChanged(this.viewer, 'streetLabels', 0.25);
      }
      this.schedule(200);
    } else {
      this.removeListener?.();
      this.removeListener = undefined;
      releaseCameraPercentageChanged(this.viewer, 'streetLabels');
      this.controller?.abort();
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

  /**
   * The ground area to label, centred on the camera's own ground position
   * (the point directly below the camera). We deliberately do NOT centre on the
   * screen-centre pick: in a tilted chase view the crosshair shoots toward the
   * horizon, so labels would load tens of km ahead of the user instead of
   * around them. And we don't use camera.computeViewRectangle() — in a tilted
   * view it returns null / a huge rectangle, which made labels never load.
   */
  private viewArea(): { s: number; w: number; n: number; e: number } | null {
    const carto = Cesium.Cartographic.fromCartesian(this.viewer.camera.positionWC);
    const lon = Cesium.Math.toDegrees(carto.longitude);
    const lat = Cesium.Math.toDegrees(carto.latitude);
    if (!isFinite(lon) || !isFinite(lat)) return null;
    // Span grows with altitude but is floored so we always cover a readable
    // neighbourhood (~4 km), and capped so we never over-fetch.
    const half = Math.min(Math.max((carto.height / 111000) * 0.9, 0.02), MAX_SPAN_DEG / 2);
    const cosLat = Math.max(Math.cos(Cesium.Math.toRadians(lat)), 0.2);
    return { s: lat - half, n: lat + half, w: lon - half / cosLat, e: lon + half / cosLat };
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
    const area = this.viewArea();
    if (!area) return;
    const { s, w, n, e } = area;

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
      const fetched = await this.fetchLabels(s, w, n, e, controller.signal);
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
    signal: AbortSignal,
  ): Promise<{ lon: number; lat: number; text: string; kind: 'road' | 'place' }[] | null> {
    const bbox = `${s},${w},${n},${e}`;
    const query =
      `[out:json][timeout:20];(` +
      `way["highway"~"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|pedestrian)$"]["name"](${bbox});` +
      `node["place"~"^(city|town|village|suburb|neighbourhood)$"]["name"](${bbox});` +
      `);out geom ${MAX_LABELS * 4};`;
    const data = await overpassQuery<OverpassWay>(query, { signal });
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
        verticalOrigin: Cesium.VerticalOrigin.CENTER,
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        // Clamp directly to the photoreal 3D tiles so names sit on the road.
        // CLAMP_TO_GROUND would snap to the ellipsoid (sea level), which is far
        // below the tiles, burying the labels; CLAMP_TO_3D_TILE tracks the real
        // surface every frame with no manual height sampling.
        heightReference: Cesium.HeightReference.CLAMP_TO_3D_TILE,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: new Cesium.NearFarScalar(200, 1, 3000, place ? 0.75 : 0.55),
        translucencyByDistance: new Cesium.NearFarScalar(1800, 1, 3000, 0),
      });
    }
    this.viewer.scene.requestRender();
  }
}
