import * as Cesium from 'cesium';
import { getActiveToken } from './config';
import type { Place } from './places';
import { bearingDeg, type LngLat } from './geo';
import { categoryById, DEFAULT_PIN_COLOR } from './categories';

/** A place that can be dropped as a map pin. */
export interface PlacePin {
  name: string;
  detail: string;
  lon: number;
  lat: number;
  categoryId?: string;
  osmType?: 'node' | 'way' | 'relation';
  osmId?: number;
  phone?: string;
  website?: string;
  openingHours?: string;
  address?: string;
}

/** Cesium ion asset ID for Google Photorealistic 3D Tiles (photoreal buildings + terrain). */
const GOOGLE_PHOTOREAL_ASSET_ID = 2275207;

export interface SearchResult {
  displayName: string;
  destination: Cesium.Cartesian3 | Cesium.Rectangle;
}

export interface LocationFix {
  lon: number;
  lat: number;
  accuracy?: number;
  heading?: number | null;
}

interface LocationState {
  lon: number;
  lat: number;
  accuracy: number;
  heading: number | null;
  height: number;
  position: Cesium.Cartesian3;
}

const toRad = Cesium.Math.toRadians;
const ACCENT = Cesium.Color.fromCssColorString('#0A84FF'); // "you are here" GPS dot (blue)
const WHITE = Cesium.Color.WHITE;
const WAYPOINT_COLOR = Cesium.Color.fromCssColorString('#FF9F0A');
const TRACK_COLOR = Cesium.Color.fromCssColorString('#FF375F');

export class Globe {
  readonly viewer: Cesium.Viewer;
  private photoreal?: Cesium.Cesium3DTileset;
  private geocoder?: Cesium.IonGeocoderService;

  private routeEntities: Cesium.Entity[] = [];

  // Live location + follow camera.
  private locationEntity?: Cesium.Entity;
  private locationState?: LocationState;
  private followActive = false;
  private followExit?: () => void;
  private onFollowChange?: (on: boolean) => void;
  private navigating = false;

  // Dropped place pins (search results / nearby categories).
  private placeMarkers: { entity: Cesium.Entity; place: PlacePin }[] = [];
  private onPlaceTapCb?: (place: PlacePin) => void;
  private pickHandler?: Cesium.ScreenSpaceEventHandler;

  // Waypoints + track recording.
  private waypointEntities = new Map<string, Cesium.Entity>();
  private trackPositions: Cesium.Cartesian3[] = [];
  private trackEntity?: Cesium.Entity;

  // Guided-drive animation state.
  private drivePath: { cart: Cesium.Cartesian3; lonlat: LngLat }[] = [];
  private driveCumulative: number[] = [];
  private driveRaf?: number;

  // Route rendering state (positions are clamped to the photoreal surface).
  private altPaths: Cesium.Cartesian3[][] = [];
  private routeStart?: Cesium.Entity;
  private routeEnd?: Cesium.Entity;
  private routeClampToken = 0;

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
      // Only render when something actually changes (camera moves, tiles load,
      // an overlay updates). Hugely reduces GPU/CPU use — faster and cooler,
      // especially on phones — with no visual difference for an explorer app.
      requestRenderMode: true,
      maximumRenderTimeChange: Infinity,
    });

    this.tuneScene();
    this.setupPicking();
    if (import.meta.env.DEV) (window as unknown as { __Cesium: typeof Cesium }).__Cesium = Cesium;
  }

  /** Tapping a dropped pin selects that place (opens its card). */
  private setupPicking(): void {
    this.pickHandler = new Cesium.ScreenSpaceEventHandler(this.viewer.canvas);
    this.pickHandler.setInputAction((movement: { position: Cesium.Cartesian2 }) => {
      const picked = this.viewer.scene.pick(movement.position);
      const marker = picked?.id && this.placeMarkers.find((m) => m.entity === picked.id);
      if (marker) this.onPlaceTapCb?.(marker.place);
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK);
  }

  onPlaceTap(cb: (place: PlacePin) => void): void {
    this.onPlaceTapCb = cb;
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
    // Cap the render resolution: on high-DPI phones 1.5x looks crisp while
    // rendering far fewer pixels than the native 3x, so it stays smooth.
    this.viewer.resolutionScale = Math.min(window.devicePixelRatio || 1, 1.5);

    const ctrl = scene.screenSpaceCameraController;
    ctrl.enableCollisionDetection = true;
    ctrl.minimumZoomDistance = 3;
    ctrl.inertiaSpin = 0.85;
    ctrl.inertiaTranslate = 0.85;
    ctrl.inertiaZoom = 0.85;
  }

  /** Loads Google Photorealistic 3D Tiles. */
  async initPhotoreal(): Promise<void> {
    this.photoreal = await Cesium.Cesium3DTileset.fromIonAssetId(
      GOOGLE_PHOTOREAL_ASSET_ID,
      {
        // 16 is Google's recommended default — noticeably faster to stream and
        // render than an aggressive value, with negligible quality loss.
        maximumScreenSpaceError: 16,
        // Cap GPU memory so tiles are recycled instead of piling up on mobile.
        cacheBytes: 512 * 1024 * 1024,
        maximumCacheOverflowBytes: 256 * 1024 * 1024,
      },
    );
    this.viewer.scene.primitives.add(this.photoreal);
    this.viewer.scene.requestRender();
  }

  flyToPlace(place: Place, duration = 3.4): void {
    this.cancelDrive();
    this.setFollow(false);
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
    this.setFollow(false);
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(-30, 25, 24_000_000),
      orientation: { heading: 0, pitch: toRad(-90), roll: 0 },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  flyToLonLat(lon: number, lat: number, height = 1200, heading = 0, pitch = -35, duration = 3): void {
    this.cancelDrive();
    this.setFollow(false);
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lon, lat, height),
      orientation: { heading: toRad(heading), pitch: toRad(pitch), roll: 0 },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  // ---------- Map controls (compass / zoom / tilt) ----------

  /** Current camera heading in degrees (0 = north up). */
  headingDeg(): number {
    return Cesium.Math.toDegrees(this.viewer.camera.heading);
  }

  /** Subscribe to camera moves (used to spin the compass needle). */
  onCameraChange(cb: () => void): void {
    this.viewer.camera.percentageChanged = 0.02;
    this.viewer.camera.changed.addEventListener(cb);
  }

  zoomIn(): void {
    this.viewer.camera.zoomIn(this.zoomStep());
    this.viewer.scene.requestRender();
  }

  zoomOut(): void {
    this.viewer.camera.zoomOut(this.zoomStep());
    this.viewer.scene.requestRender();
  }

  private zoomStep(): number {
    const h = this.viewer.camera.positionCartographic?.height ?? 1000;
    return Cesium.Math.clamp(h * 0.35, 5, 6_000_000);
  }

  /** Rotate the view back to north-up, keeping the current pitch and target. */
  resetNorth(): void {
    this.setFollow(false);
    const camera = this.viewer.camera;
    camera.flyTo({
      destination: camera.positionWC.clone(),
      orientation: { heading: 0, pitch: camera.pitch, roll: 0 },
      duration: 0.6,
    });
  }

  /** Toggle between a tilted 3D view and a near-top-down "2D" view. */
  toggleTilt(): void {
    const center = this.cameraCenterLonLat();
    if (!center) return;
    this.setFollow(false);
    const height = this.viewer.camera.positionCartographic?.height ?? 1500;
    const topDown = Cesium.Math.toDegrees(this.viewer.camera.pitch) < -68;
    const pitch = topDown ? -35 : -85;
    this.flyToLonLat(center[0], center[1], height, this.headingDeg(), pitch, 0.8);
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

  // ---------- Place pins (Apple-style teardrop markers) ----------

  /**
   * Drop clean teardrop pins for a set of places. Pins are colored by category
   * (food, hotels, …) and are clearly distinct from the blue "you are here"
   * GPS dot. Replaces any pins from a previous search.
   */
  showPlaces(places: PlacePin[]): void {
    this.clearPlaces();
    for (const place of places) this.addPin(place);
    this.viewer.scene.requestRender();
  }

  private addPin(place: PlacePin): void {
    const cat = categoryById(place.categoryId);
    const image = pinImage(cat?.color ?? DEFAULT_PIN_COLOR, cat?.glyph ?? '');
    const entity = this.viewer.entities.add({
      position: Cesium.Cartesian3.fromDegrees(place.lon, place.lat, 0),
      billboard: {
        image,
        width: 42,
        height: 55,
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: new Cesium.NearFarScalar(200, 1, 45000, 0.55),
      },
      label: {
        text: place.name,
        font: '600 14px -apple-system, BlinkMacSystemFont, system-ui, sans-serif',
        fillColor: WHITE,
        showBackground: true,
        backgroundColor: new Cesium.Color(0, 0, 0, 0.66),
        backgroundPadding: new Cesium.Cartesian2(9, 6),
        pixelOffset: new Cesium.Cartesian2(0, -60),
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: new Cesium.NearFarScalar(200, 1, 12000, 0.65),
        translucencyByDistance: new Cesium.NearFarScalar(9000, 1, 16000, 0),
        style: Cesium.LabelStyle.FILL,
      },
    });
    this.placeMarkers.push({ entity, place });
    void this.refinePinHeight(entity, place.lon, place.lat);
  }

  private async refinePinHeight(entity: Cesium.Entity, lon: number, lat: number): Promise<void> {
    const h = await this.sampleHeight(lon, lat);
    if (h === null) return;
    entity.position = new Cesium.ConstantPositionProperty(
      Cesium.Cartesian3.fromDegrees(lon, lat, h),
    );
    this.viewer.scene.requestRender();
  }

  /**
   * Fly in and look *at* a place from an oblique angle (like Apple Maps' "look
   * around"), keeping the pin centered in view rather than hovering above it.
   */
  focusPlace(place: PlacePin): void {
    this.cancelDrive();
    this.setFollow(false);
    void this.flyLookAt(place.lon, place.lat);
  }

  private async flyLookAt(lon: number, lat: number): Promise<void> {
    const h = (await this.sampleHeight(lon, lat)) ?? 0;
    const center = Cesium.Cartesian3.fromDegrees(lon, lat, h);
    // Orbit the camera back from the pin (range) at a natural downward pitch so
    // the pin stays centered; heading from the south gives a pleasant 3D view.
    this.viewer.camera.flyToBoundingSphere(new Cesium.BoundingSphere(center, 45), {
      duration: 2.2,
      offset: new Cesium.HeadingPitchRange(toRad(0), toRad(-30), 400),
    });
    this.viewer.scene.requestRender();
  }

  /** Fit the camera to see all currently dropped pins. */
  framePlaces(): void {
    this.cancelDrive();
    this.setFollow(false);
    if (this.placeMarkers.length === 0) return;
    if (this.placeMarkers.length === 1) {
      this.focusPlace(this.placeMarkers[0].place);
      return;
    }
    void this.viewer.flyTo(
      this.placeMarkers.map((m) => m.entity),
      { duration: 2, offset: new Cesium.HeadingPitchRange(toRad(0), toRad(-50), 0) },
    );
  }

  clearPlaces(): void {
    for (const m of this.placeMarkers) this.viewer.entities.remove(m.entity);
    this.placeMarkers = [];
    this.viewer.scene.requestRender();
  }

  /** The [lon, lat] the camera is currently centered on (best-effort). */
  cameraCenterLonLat(): LngLat | null {
    const center = new Cesium.Cartesian2(
      this.viewer.canvas.clientWidth / 2,
      this.viewer.canvas.clientHeight / 2,
    );
    const ray = this.viewer.camera.getPickRay(center);
    const pos =
      this.viewer.scene.pickPosition(center) ??
      (ray ? this.viewer.scene.globe.pick(ray, this.viewer.scene) : undefined);
    if (!pos) return null;
    const carto = Cesium.Cartographic.fromCartesian(pos);
    return [Cesium.Math.toDegrees(carto.longitude), Cesium.Math.toDegrees(carto.latitude)];
  }

  // ---------- Surface height sampling ----------

  /**
   * Height (ellipsoidal, meters) of the photoreal surface at a coordinate, or
   * null if it can't be resolved. Values are plausibility-checked so a partly
   * loaded tile can't return an absurd height that buries the dot/camera.
   */
  async sampleHeight(lon: number, lat: number): Promise<number | null> {
    const scene = this.viewer.scene;
    const base = Cesium.Cartesian3.fromDegrees(lon, lat, 0);
    const sync = scene.clampToHeight(base);
    if (sync) {
      const h = Cesium.Cartographic.fromCartesian(sync).height;
      if (plausibleHeight(h)) return h;
    }
    try {
      const res = await scene.clampToHeightMostDetailed([Cesium.Cartesian3.fromDegrees(lon, lat, 0)]);
      if (res[0]) {
        const h = Cesium.Cartographic.fromCartesian(res[0]).height;
        if (plausibleHeight(h)) return h;
      }
    } catch {
      /* tiles not ready */
    }
    return null;
  }

  // ---------- Live location (Apple-style blue dot) ----------

  onFollow(cb: (on: boolean) => void): void {
    this.onFollowChange = cb;
  }

  isFollowing(): boolean {
    return this.followActive;
  }

  hasLocation(): boolean {
    return !!this.locationState;
  }

  /** Update (or create) the user location dot, keeping it on the surface. */
  updateLocation(fix: LocationFix): void {
    const height = this.locationState?.height ?? 0;
    const state: LocationState = {
      lon: fix.lon,
      lat: fix.lat,
      accuracy: Math.max(fix.accuracy ?? 8, 4),
      heading: fix.heading ?? null,
      height,
      position: Cesium.Cartesian3.fromDegrees(fix.lon, fix.lat, height),
    };
    this.locationState = state;

    if (!this.locationEntity) this.createLocationEntity();
    else this.locationEntity.show = true;

    if (this.followActive) this.applyFollow(true);
    this.viewer.scene.requestRender();

    void this.refineLocationHeight(fix.lon, fix.lat);
  }

  private async refineLocationHeight(lon: number, lat: number): Promise<void> {
    const h = await this.sampleHeight(lon, lat);
    if (h === null) return; // keep the provisional height until tiles resolve
    const s = this.locationState;
    if (!s || s.lon !== lon || s.lat !== lat) return; // superseded by a newer fix
    s.height = h;
    s.position = Cesium.Cartesian3.fromDegrees(lon, lat, h);
    if (this.followActive) this.applyFollow(true);
    this.viewer.scene.requestRender();
  }

  private createLocationEntity(): void {
    const num = (get: () => number | undefined, fallback: number) =>
      new Cesium.CallbackProperty(() => get() ?? fallback, false);

    this.locationEntity = this.viewer.entities.add({
      position: new Cesium.CallbackProperty(
        () => this.locationState?.position ?? Cesium.Cartesian3.ZERO,
        false,
      ) as unknown as Cesium.PositionProperty,
      ellipse: {
        semiMajorAxis: num(() => this.locationState?.accuracy, 8),
        semiMinorAxis: num(() => this.locationState?.accuracy, 8),
        height: num(() => this.locationState?.height, 0),
        material: ACCENT.withAlpha(0.14),
        outline: true,
        outlineColor: ACCENT.withAlpha(0.5),
        outlineWidth: 1,
      },
      point: {
        pixelSize: 15,
        color: ACCENT,
        outlineColor: WHITE,
        outlineWidth: 3,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
  }

  clearLocation(): void {
    this.setFollow(false);
    if (this.locationEntity) {
      this.viewer.entities.remove(this.locationEntity);
      this.locationEntity = undefined;
    }
    this.locationState = undefined;
    this.viewer.scene.requestRender();
  }

  /** Enter/leave a chase camera that looks at and follows the location dot. */
  setFollow(on: boolean): void {
    if (on && !this.locationState) return;
    if (on === this.followActive) {
      if (on) this.applyFollow(false);
      return;
    }
    this.followActive = on;
    if (on) {
      this.applyFollow(false);
      // Any manual camera interaction drops out of follow mode.
      this.followExit = () => this.setFollow(false);
      this.viewer.canvas.addEventListener('pointerdown', this.followExit, { once: true });
    } else if (this.followExit) {
      this.viewer.canvas.removeEventListener('pointerdown', this.followExit);
      this.followExit = undefined;
    }
    this.onFollowChange?.(this.followActive);
  }

  private applyFollow(instant: boolean): void {
    const s = this.locationState;
    if (!s) return;
    const hRad = toRad(s.heading ?? 0);
    const frame = Cesium.Transforms.eastNorthUpToFixedFrame(s.position);
    const back = 150;
    const up = 75;
    const local = new Cesium.Cartesian3(-Math.sin(hRad) * back, -Math.cos(hRad) * back, up);
    const camPos = Cesium.Matrix4.multiplyByPoint(frame, local, new Cesium.Cartesian3());
    const orientation = { heading: hRad, pitch: toRad(-28), roll: 0 };
    if (instant) {
      this.viewer.camera.setView({ destination: camPos, orientation });
      this.viewer.scene.requestRender();
    } else {
      this.cancelDrive();
      this.viewer.camera.flyTo({
        destination: camPos,
        orientation,
        duration: 1.4,
        easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
      });
    }
  }

  // ---------- Navigation chase camera ----------

  beginNavigation(): void {
    this.navigating = true;
    this.setFollow(false);
  }

  endNavigation(): void {
    this.navigating = false;
  }

  isNavigating(): boolean {
    return this.navigating;
  }

  /**
   * Turn-by-turn chase camera: sit just behind and above the live GPS position,
   * looking along the direction of travel (`courseDeg`) — the Apple Maps 3D
   * driving view. Called on every GPS fix while guiding.
   */
  updateNavCamera(courseDeg: number, smooth = false): void {
    const s = this.locationState;
    if (!s) return;
    const hRad = toRad(courseDeg);
    const frame = Cesium.Transforms.eastNorthUpToFixedFrame(s.position);
    const back = 95;
    const up = 52;
    const local = new Cesium.Cartesian3(-Math.sin(hRad) * back, -Math.cos(hRad) * back, up);
    const camPos = Cesium.Matrix4.multiplyByPoint(frame, local, new Cesium.Cartesian3());
    const orientation = { heading: hRad, pitch: toRad(-22), roll: 0 };
    if (smooth) {
      this.viewer.camera.flyTo({
        destination: camPos,
        orientation,
        duration: 1.2,
        easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
      });
    } else {
      this.viewer.camera.setView({ destination: camPos, orientation });
    }
    this.viewer.scene.requestRender();
  }

  // ---------- Waypoints ----------

  addWaypoint(id: string, lon: number, lat: number, label: string): void {
    this.removeWaypoint(id);
    const entity = this.viewer.entities.add({
      position: Cesium.Cartesian3.fromDegrees(lon, lat, 0),
      point: {
        pixelSize: 12,
        color: WAYPOINT_COLOR,
        outlineColor: WHITE,
        outlineWidth: 2.5,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: label,
        font: '600 13px -apple-system, BlinkMacSystemFont, system-ui, sans-serif',
        fillColor: WHITE,
        showBackground: true,
        backgroundColor: new Cesium.Color(0, 0, 0, 0.55),
        backgroundPadding: new Cesium.Cartesian2(8, 5),
        pixelOffset: new Cesium.Cartesian2(0, -22),
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: new Cesium.NearFarScalar(300, 1, 12000, 0.55),
      },
    });
    this.waypointEntities.set(id, entity);
    void this.refineWaypointHeight(id, lon, lat);
    this.viewer.scene.requestRender();
  }

  private async refineWaypointHeight(id: string, lon: number, lat: number): Promise<void> {
    const h = await this.sampleHeight(lon, lat);
    if (h === null) return;
    const entity = this.waypointEntities.get(id);
    if (!entity) return;
    entity.position = new Cesium.ConstantPositionProperty(
      Cesium.Cartesian3.fromDegrees(lon, lat, h),
    );
    this.viewer.scene.requestRender();
  }

  removeWaypoint(id: string): void {
    const entity = this.waypointEntities.get(id);
    if (entity) {
      this.viewer.entities.remove(entity);
      this.waypointEntities.delete(id);
      this.viewer.scene.requestRender();
    }
  }

  clearWaypoints(): void {
    for (const e of this.waypointEntities.values()) this.viewer.entities.remove(e);
    this.waypointEntities.clear();
    this.viewer.scene.requestRender();
  }

  // ---------- Track recording (breadcrumb trail) ----------

  beginTrack(): void {
    this.clearTrack();
    this.trackEntity = this.viewer.entities.add({
      polyline: {
        positions: new Cesium.CallbackProperty(() => this.trackPositions, false),
        width: 7,
        material: new Cesium.PolylineGlowMaterialProperty({ glowPower: 0.25, color: TRACK_COLOR }),
        depthFailMaterial: new Cesium.ColorMaterialProperty(TRACK_COLOR.withAlpha(0.5)),
      },
    });
  }

  async pushTrackPoint(lon: number, lat: number): Promise<void> {
    const h = (await this.sampleHeight(lon, lat)) ?? this.locationState?.height ?? 0;
    this.trackPositions.push(Cesium.Cartesian3.fromDegrees(lon, lat, h + 2));
    this.viewer.scene.requestRender();
  }

  clearTrack(): void {
    if (this.trackEntity) {
      this.viewer.entities.remove(this.trackEntity);
      this.trackEntity = undefined;
    }
    this.trackPositions = [];
    this.viewer.scene.requestRender();
  }

  // ---------- Routing overlays ----------

  clearRoute(): void {
    this.cancelDrive();
    this.routeClampToken++;
    for (const e of this.routeEntities) this.viewer.entities.remove(e);
    this.routeEntities = [];
    this.altPaths = [];
    this.routeStart = undefined;
    this.routeEnd = undefined;
    this.drivePath = [];
    this.driveCumulative = [];
    this.viewer.scene.requestRender();
  }

  /**
   * Draws a route polyline with endpoints. Positions start at a provisional
   * height and are then clamped onto the photoreal surface so the line hugs the
   * ground/roads instead of floating (or sinking) through the map. A depth-fail
   * material keeps it visible where buildings would otherwise occlude it.
   */
  showRoute(coordinates: LngLat[]): void {
    this.clearRoute();
    this.drawSelectedRoute(coordinates);
  }

  private drawSelectedRoute(coordinates: LngLat[]): void {
    const sampled = downsample(coordinates, 300);

    const path = sampled.map((lonlat) => ({
      cart: Cesium.Cartesian3.fromDegrees(lonlat[0], lonlat[1], 2),
      lonlat,
    }));
    this.drivePath = path;
    this.driveCumulative = cumulativeDistances(path.map((p) => p.lonlat));

    const line = this.viewer.entities.add({
      polyline: {
        positions: new Cesium.CallbackProperty(() => this.drivePath.map((p) => p.cart), false),
        width: 9,
        material: new Cesium.PolylineGlowMaterialProperty({ glowPower: 0.22, color: ACCENT }),
        depthFailMaterial: new Cesium.ColorMaterialProperty(ACCENT.withAlpha(0.55)),
      },
    });
    this.routeStart = this.pin(path[0].cart, Cesium.Color.fromCssColorString('#32D74B'));
    this.routeEnd = this.pin(path[path.length - 1].cart, Cesium.Color.fromCssColorString('#FF453A'));
    this.routeEntities.push(line, this.routeStart, this.routeEnd);
    this.viewer.scene.requestRender();
    void this.clampSelectedRoute(sampled);
  }

  /**
   * Draw the selected route plus dimmed alternates (Apple-Maps style). The
   * selected route gets the glowing accent line and start/end pins; alternates
   * render as muted gray lines behind it. All lines are clamped to the surface.
   */
  showRouteWithAlternates(selected: LngLat[], others: LngLat[][]): void {
    this.clearRoute();
    others.forEach((alt) => {
      const sampled = downsample(alt, 300);
      const carts = sampled.map((c) => Cesium.Cartesian3.fromDegrees(c[0], c[1], 2));
      const idx = this.altPaths.push(carts) - 1;
      const line = this.viewer.entities.add({
        polyline: {
          positions: new Cesium.CallbackProperty(() => this.altPaths[idx], false),
          width: 7,
          material: new Cesium.ColorMaterialProperty(Cesium.Color.fromCssColorString('#8E8E93').withAlpha(0.55)),
          depthFailMaterial: new Cesium.ColorMaterialProperty(Cesium.Color.fromCssColorString('#8E8E93').withAlpha(0.32)),
        },
      });
      this.routeEntities.push(line);
      void this.clampAlternate(idx, sampled);
    });
    this.drawSelectedRoute(selected);
  }

  /** Batch-clamp the route vertices onto the photoreal surface, then redraw. */
  private async clampSelectedRoute(sampled: LngLat[]): Promise<void> {
    const token = this.routeClampToken;
    const heights = await this.sampleHeights(sampled);
    if (token !== this.routeClampToken) return; // route changed/cleared
    for (let i = 0; i < heights.length && i < this.drivePath.length; i++) {
      const h = heights[i];
      if (h === null) continue;
      this.drivePath[i].cart = Cesium.Cartesian3.fromDegrees(sampled[i][0], sampled[i][1], h + 1.5);
    }
    if (this.routeStart) this.routeStart.position = new Cesium.ConstantPositionProperty(this.drivePath[0].cart);
    if (this.routeEnd) {
      this.routeEnd.position = new Cesium.ConstantPositionProperty(this.drivePath[this.drivePath.length - 1].cart);
    }
    this.viewer.scene.requestRender();
  }

  private async clampAlternate(idx: number, sampled: LngLat[]): Promise<void> {
    const token = this.routeClampToken;
    const heights = await this.sampleHeights(sampled);
    if (token !== this.routeClampToken) return;
    const arr = this.altPaths[idx];
    if (!arr) return;
    for (let i = 0; i < heights.length && i < arr.length; i++) {
      const h = heights[i];
      if (h === null) continue;
      arr[i] = Cesium.Cartesian3.fromDegrees(sampled[i][0], sampled[i][1], h + 1.2);
    }
    this.viewer.scene.requestRender();
  }

  /** Clamp a batch of coordinates to the photoreal surface (heights or null). */
  private async sampleHeights(coords: LngLat[]): Promise<(number | null)[]> {
    const flat = coords.map((c) => Cesium.Cartesian3.fromDegrees(c[0], c[1], 0));
    try {
      const clamped = await this.viewer.scene.clampToHeightMostDetailed(flat);
      return clamped.map((c) => {
        if (!c) return null;
        const h = Cesium.Cartographic.fromCartesian(c).height;
        return plausibleHeight(h) ? h : null;
      });
    } catch {
      return coords.map(() => null);
    }
  }

  private pin(position: Cesium.Cartesian3, color: Cesium.Color): Cesium.Entity {
    return this.viewer.entities.add({
      position,
      point: {
        pixelSize: 14,
        color,
        outlineColor: WHITE,
        outlineWidth: 2.5,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
  }

  /** Fit the camera to see the whole route. */
  frameRoute(): void {
    this.cancelDrive();
    this.setFollow(false);
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
    this.viewer.scene.requestRender();
  }

  destroy(): void {
    this.cancelDrive();
    this.pickHandler?.destroy();
    if (!this.viewer.isDestroyed()) this.viewer.destroy();
  }
}

// ---------- Pin image generation ----------

const pinCache = new Map<string, string>();

/**
 * A refined Apple-style teardrop pin as an SVG data URI: a glossy, vertically
 * shaded colored drop with a soft drop shadow, a floating ground shadow, and a
 * white head holding a category glyph (or a clean dot for plain results).
 */
function pinImage(color: string, glyph: string): string {
  const key = `${color}|${glyph}`;
  const cached = pinCache.get(key);
  if (cached) return cached;

  const light = mixWithWhite(color, 0.3);
  const head = glyph
    ? `<circle cx="32" cy="30" r="13.5" fill="#fff"/>` +
      `<circle cx="32" cy="30" r="13.5" fill="none" stroke="${color}" stroke-opacity="0.15" stroke-width="1"/>` +
      `<g transform="translate(20 18) scale(0.833)" fill="none" stroke="${color}" ` +
      `stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${glyph}</g>`
    : `<circle cx="32" cy="30" r="7.5" fill="#fff"/>` +
      `<circle cx="32" cy="30" r="3.4" fill="${color}"/>`;

  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="84" viewBox="0 0 64 84">` +
    `<defs>` +
    `<linearGradient id="pg" x1="0" y1="0" x2="0" y2="1">` +
    `<stop offset="0" stop-color="${light}"/><stop offset="1" stop-color="${color}"/>` +
    `</linearGradient>` +
    `<filter id="ps" x="-40%" y="-30%" width="180%" height="170%">` +
    `<feDropShadow dx="0" dy="1.5" stdDeviation="2" flood-color="#000" flood-opacity="0.45"/>` +
    `</filter>` +
    `</defs>` +
    `<ellipse cx="32" cy="79.5" rx="7" ry="2.2" fill="#000" opacity="0.22"/>` +
    `<path d="M32 77 C21 58 8 46 8 30 A24 24 0 1 1 56 30 C56 46 43 58 32 77 Z" ` +
    `fill="url(#pg)" stroke="#fff" stroke-width="3" filter="url(#ps)"/>` +
    `<ellipse cx="32" cy="19" rx="15" ry="8.5" fill="#fff" opacity="0.18"/>` +
    `${head}</svg>`;

  const uri = `data:image/svg+xml,${encodeURIComponent(svg)}`;
  pinCache.set(key, uri);
  return uri;
}

/** Blend a #rrggbb color toward white by `amt` (0–1), returning an rgb() string. */
function mixWithWhite(hex: string, amt: number): string {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim());
  if (!m) return hex;
  const mix = (h: string) => {
    const c = parseInt(h, 16);
    return Math.round(c + (255 - c) * amt);
  };
  return `rgb(${mix(m[1])}, ${mix(m[2])}, ${mix(m[3])})`;
}

// ---------- helpers ----------

/** Earth's real surface sits within this ellipsoidal-height band. */
function plausibleHeight(h: number): boolean {
  return Number.isFinite(h) && h > -500 && h < 9000;
}

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
