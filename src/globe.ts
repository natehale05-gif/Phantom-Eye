import * as Cesium from 'cesium';
import { getActiveToken } from './config';
import type { Place } from './places';
import { bearingDeg, type LngLat } from './geo';

/** Cesium ion asset ID for Google Photorealistic 3D Tiles (photoreal buildings + terrain). */
const GOOGLE_PHOTOREAL_ASSET_ID = 2275207;

export interface SearchResult {
  displayName: string;
  destination: Cesium.Cartesian3 | Cesium.Rectangle;
}

const toRad = Cesium.Math.toRadians;
const ACCENT = Cesium.Color.fromCssColorString('#0A84FF');

export class Globe {
  readonly viewer: Cesium.Viewer;
  private photoreal?: Cesium.Cesium3DTileset;
  private geocoder?: Cesium.IonGeocoderService;

  private routeEntities: Cesium.Entity[] = [];
  private locationEntity?: Cesium.Entity;

  // Guided-drive animation state.
  private drivePath: { cart: Cesium.Cartesian3; lonlat: LngLat }[] = [];
  private driveCumulative: number[] = [];
  private driveRaf?: number;

  constructor(container: HTMLElement, creditContainer: HTMLElement) {
    Cesium.Ion.defaultAccessToken = getActiveToken();

    this.viewer = new Cesium.Viewer(container, {
      baseLayerPicker: false,
      geocoder: false,
      homeButton: false,
      sceneModePicker: false,
      navigationHelpButton: false,
      navigationInstructionsInitiallyVisible: false,
      animation: false,
      timeline: false,
      fullscreenButton: false,
      infoBox: false,
      selectionIndicator: false,
      creditContainer,
      baseLayer: false,
    });

    this.tuneScene();
  }

  /** Cinematic, premium look: soft atmosphere, lighting, anti-aliasing. */
  private tuneScene(): void {
    const { scene } = this.viewer;

    if (scene.skyAtmosphere) scene.skyAtmosphere.show = true;
    scene.fog.enabled = true;
    scene.fog.density = 0.0002;
    scene.globe.enableLighting = true;
    scene.globe.showGroundAtmosphere = true;
    scene.globe.baseColor = Cesium.Color.fromCssColorString('#05080f');

    // Photoreal tiles are the surface, so the reference ellipsoid stays hidden.
    scene.globe.show = false;

    if (scene.postProcessStages.fxaa) scene.postProcessStages.fxaa.enabled = true;
    try {
      scene.highDynamicRange = true;
    } catch {
      /* not supported on all GPUs */
    }
    this.viewer.resolutionScale = Math.min(window.devicePixelRatio || 1, 2);

    const ctrl = scene.screenSpaceCameraController;
    ctrl.enableCollisionDetection = true;
    ctrl.minimumZoomDistance = 5;
    ctrl.inertiaSpin = 0.85;
    ctrl.inertiaTranslate = 0.85;
    ctrl.inertiaZoom = 0.85;
  }

  /** Loads Google Photorealistic 3D Tiles. */
  async initPhotoreal(): Promise<void> {
    this.photoreal = await Cesium.Cesium3DTileset.fromIonAssetId(
      GOOGLE_PHOTOREAL_ASSET_ID,
      { maximumScreenSpaceError: 12 },
    );
    this.viewer.scene.primitives.add(this.photoreal);
    this.viewer.scene.requestRender();
  }

  flyToPlace(place: Place, duration = 3.4): void {
    this.cancelDrive();
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(place.lon, place.lat, place.height),
      orientation: { heading: toRad(place.heading), pitch: toRad(place.pitch), roll: 0 },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  /** Frame the whole planet. Duration 0 snaps instantly (used on boot). */
  flyWholePlanet(duration = 0): void {
    this.cancelDrive();
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(-30, 25, 24_000_000),
      orientation: { heading: 0, pitch: toRad(-90), roll: 0 },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  flyToLonLat(lon: number, lat: number, height = 1200, heading = 0, pitch = -35, duration = 3): void {
    this.cancelDrive();
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lon, lat, height),
      orientation: { heading: toRad(heading), pitch: toRad(pitch), roll: 0 },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  async search(query: string): Promise<SearchResult[]> {
    if (!this.geocoder) {
      this.geocoder = new Cesium.IonGeocoderService({ scene: this.viewer.scene });
    }
    const results = await this.geocoder.geocode(query.trim());
    return results.map((r) => ({ displayName: r.displayName, destination: r.destination }));
  }

  /** Resolve a geocoder destination to a representative [lon, lat]. */
  static destinationLonLat(destination: Cesium.Cartesian3 | Cesium.Rectangle): LngLat {
    if (destination instanceof Cesium.Rectangle) {
      const c = Cesium.Rectangle.center(destination);
      return [Cesium.Math.toDegrees(c.longitude), Cesium.Math.toDegrees(c.latitude)];
    }
    const carto = Cesium.Cartographic.fromCartesian(destination);
    return [Cesium.Math.toDegrees(carto.longitude), Cesium.Math.toDegrees(carto.latitude)];
  }

  flyToDestination(destination: Cesium.Cartesian3 | Cesium.Rectangle): void {
    const [lon, lat] = Globe.destinationLonLat(destination);
    let height = 1500;
    if (destination instanceof Cesium.Rectangle) {
      const diag = Cesium.Cartesian3.distance(
        Cesium.Cartographic.toCartesian(Cesium.Rectangle.northeast(destination)),
        Cesium.Cartographic.toCartesian(Cesium.Rectangle.southwest(destination)),
      );
      height = Cesium.Math.clamp(diag * 0.9, 600, 4_000_000);
    }
    this.flyToLonLat(lon, lat, height, 20, -35, 3.2);
  }

  /** The [lon, lat] the camera is currently centered on (best-effort). */
  cameraCenterLonLat(): LngLat | null {
    const ray = this.viewer.camera.getPickRay(
      new Cesium.Cartesian2(
        this.viewer.canvas.clientWidth / 2,
        this.viewer.canvas.clientHeight / 2,
      ),
    );
    if (!ray) return null;
    const pos =
      this.viewer.scene.pickPosition(
        new Cesium.Cartesian2(
          this.viewer.canvas.clientWidth / 2,
          this.viewer.canvas.clientHeight / 2,
        ),
      ) ?? this.viewer.scene.globe.pick(ray, this.viewer.scene);
    if (!pos) return null;
    const carto = Cesium.Cartographic.fromCartesian(pos);
    return [Cesium.Math.toDegrees(carto.longitude), Cesium.Math.toDegrees(carto.latitude)];
  }

  // ---------- Location & routing overlays ----------

  showLocation(lon: number, lat: number): void {
    const position = Cesium.Cartesian3.fromDegrees(lon, lat, 0);
    if (this.locationEntity) this.viewer.entities.remove(this.locationEntity);
    this.locationEntity = this.viewer.entities.add({
      position,
      point: {
        pixelSize: 16,
        color: ACCENT,
        outlineColor: Cesium.Color.WHITE,
        outlineWidth: 3,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
    this.viewer.scene.requestRender();
  }

  clearRoute(): void {
    this.cancelDrive();
    for (const e of this.routeEntities) this.viewer.entities.remove(e);
    this.routeEntities = [];
    this.drivePath = [];
    this.driveCumulative = [];
    this.viewer.scene.requestRender();
  }

  /**
   * Draws a route polyline with endpoints. The line uses a depth-fail material
   * so it stays visible even where the photoreal buildings would occlude it.
   */
  showRoute(coordinates: LngLat[]): void {
    this.clearRoute();
    const sampled = downsample(coordinates, 300);

    const path = sampled.map((lonlat) => ({
      cart: Cesium.Cartesian3.fromDegrees(lonlat[0], lonlat[1], 3),
      lonlat,
    }));
    this.drivePath = path;
    this.driveCumulative = cumulativeDistances(path.map((p) => p.lonlat));

    const positions = path.map((p) => p.cart);
    const line = this.viewer.entities.add({
      polyline: {
        positions,
        width: 9,
        material: new Cesium.PolylineGlowMaterialProperty({ glowPower: 0.22, color: ACCENT }),
        depthFailMaterial: new Cesium.ColorMaterialProperty(ACCENT.withAlpha(0.55)),
      },
    });
    const start = this.pin(path[0].cart, Cesium.Color.fromCssColorString('#32D74B'));
    const end = this.pin(path[path.length - 1].cart, Cesium.Color.fromCssColorString('#FF453A'));
    this.routeEntities.push(line, start, end);
    this.viewer.scene.requestRender();
  }

  private pin(position: Cesium.Cartesian3, color: Cesium.Color): Cesium.Entity {
    return this.viewer.entities.add({
      position,
      point: {
        pixelSize: 14,
        color,
        outlineColor: Cesium.Color.WHITE,
        outlineWidth: 2.5,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
  }

  /** Fit the camera to see the whole route. */
  frameRoute(): void {
    this.cancelDrive();
    if (this.routeEntities.length === 0) return;
    this.viewer.flyTo(this.routeEntities, {
      duration: 2.2,
      offset: new Cesium.HeadingPitchRange(toRad(0), toRad(-45), 0),
    });
  }

  // ---------- Guided drive (turn-by-turn preview) ----------

  /** Animate the camera along the route, reporting the current position. */
  startDrive(onProgress: (lonlat: LngLat, remaining: number) => void, onArrive: () => void): void {
    if (this.drivePath.length < 2) return;
    this.cancelDrive();

    const total = this.driveCumulative[this.driveCumulative.length - 1];
    const speed = Math.max(18, total / 75); // finish within ~75s
    let traveled = 0;
    let last = performance.now();

    const tick = (now: number) => {
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      traveled += speed * dt;

      if (traveled >= total) {
        this.positionCameraAt(total);
        const endLonLat = this.drivePath[this.drivePath.length - 1].lonlat;
        onProgress(endLonLat, 0);
        this.driveRaf = undefined;
        onArrive();
        return;
      }

      this.positionCameraAt(traveled);
      const lonlat = this.lonLatAtDistance(traveled);
      onProgress(lonlat, total - traveled);
      this.driveRaf = requestAnimationFrame(tick);
    };
    this.driveRaf = requestAnimationFrame(tick);
  }

  cancelDrive(): void {
    if (this.driveRaf !== undefined) {
      cancelAnimationFrame(this.driveRaf);
      this.driveRaf = undefined;
    }
  }

  private segmentAtDistance(d: number): { i: number; t: number } {
    const cum = this.driveCumulative;
    for (let i = 1; i < cum.length; i++) {
      if (d <= cum[i]) {
        const segLen = cum[i] - cum[i - 1] || 1;
        return { i: i - 1, t: (d - cum[i - 1]) / segLen };
      }
    }
    return { i: cum.length - 2, t: 1 };
  }

  private lonLatAtDistance(d: number): LngLat {
    const { i, t } = this.segmentAtDistance(d);
    const a = this.drivePath[i].lonlat;
    const b = this.drivePath[i + 1].lonlat;
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  }

  private positionCameraAt(d: number): void {
    const { i, t } = this.segmentAtDistance(d);
    const a = this.drivePath[i].cart;
    const b = this.drivePath[i + 1].cart;
    const ground = Cesium.Cartesian3.lerp(a, b, t, new Cesium.Cartesian3());
    const heading = bearingDeg(this.drivePath[i].lonlat, this.drivePath[i + 1].lonlat);
    const camPos = raise(ground, 55);
    this.viewer.camera.setView({
      destination: camPos,
      orientation: { heading: toRad(heading), pitch: toRad(-28), roll: 0 },
    });
  }

  destroy(): void {
    this.cancelDrive();
    if (!this.viewer.isDestroyed()) this.viewer.destroy();
  }
}

// ---------- helpers ----------

function raise(cart: Cesium.Cartesian3, meters: number): Cesium.Cartesian3 {
  const carto = Cesium.Cartographic.fromCartesian(cart);
  return Cesium.Cartesian3.fromRadians(carto.longitude, carto.latitude, carto.height + meters);
}

function downsample(coords: LngLat[], max: number): LngLat[] {
  if (coords.length <= max) return coords;
  const step = coords.length / max;
  const out: LngLat[] = [];
  for (let i = 0; i < coords.length; i += step) out.push(coords[Math.floor(i)]);
  const last = coords[coords.length - 1];
  if (out[out.length - 1] !== last) out.push(last);
  return out;
}

function cumulativeDistances(coords: LngLat[]): number[] {
  const cum = [0];
  for (let i = 1; i < coords.length; i++) {
    cum.push(cum[i - 1] + haversineMeters(coords[i - 1], coords[i]));
  }
  return cum;
}

function haversineMeters(a: LngLat, b: LngLat): number {
  const R = 6371000;
  const toR = (d: number) => (d * Math.PI) / 180;
  const dLat = toR(b[1] - a[1]);
  const dLon = toR(b[0] - a[0]);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toR(a[1])) * Math.cos(toR(b[1])) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}
