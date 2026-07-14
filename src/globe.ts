import * as Cesium from 'cesium';
import { getActiveToken } from './config';
import type { Place } from './places';

/** Cesium ion asset ID for Google Photorealistic 3D Tiles (photoreal buildings + terrain). */
const GOOGLE_PHOTOREAL_ASSET_ID = 2275207;

export type SceneMode = 'photoreal' | 'terrain';

export interface SearchResult {
  displayName: string;
  destination: Cesium.Cartesian3 | Cesium.Rectangle;
}

const toRad = Cesium.Math.toRadians;

export class Globe {
  readonly viewer: Cesium.Viewer;
  private photoreal?: Cesium.Cesium3DTileset;
  private osmBuildings?: Cesium.Cesium3DTileset;
  private worldTerrain?: Cesium.TerrainProvider;
  private geocoder?: Cesium.IonGeocoderService;
  private mode: SceneMode = 'photoreal';

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
      // Start with a plain ellipsoid; photoreal tiles are added asynchronously.
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

    // Hide the reference ellipsoid until a real surface is loaded.
    scene.globe.show = false;

    // High quality rendering where the hardware allows it.
    if (scene.postProcessStages.fxaa) {
      scene.postProcessStages.fxaa.enabled = true;
    }
    try {
      scene.highDynamicRange = true;
    } catch {
      /* not supported on all GPUs */
    }
    this.viewer.resolutionScale = Math.min(window.devicePixelRatio || 1, 2);

    // Smoother, more natural camera interaction.
    const ctrl = scene.screenSpaceCameraController;
    ctrl.enableCollisionDetection = true;
    ctrl.minimumZoomDistance = 5;

    scene.screenSpaceCameraController.inertiaSpin = 0.85;
    scene.screenSpaceCameraController.inertiaTranslate = 0.85;
    scene.screenSpaceCameraController.inertiaZoom = 0.85;

    this.viewer.scene.debugShowFramesPerSecond = false;
  }

  /** Loads Google Photorealistic 3D Tiles and shows the globe once ready. */
  async initPhotoreal(): Promise<void> {
    this.photoreal = await Cesium.Cesium3DTileset.fromIonAssetId(
      GOOGLE_PHOTOREAL_ASSET_ID,
      {
        // Favour crisp detail near the camera.
        maximumScreenSpaceError: 12,
      },
    );
    this.viewer.scene.primitives.add(this.photoreal);
    this.applyMode('photoreal');
  }

  private async ensureTerrainMode(): Promise<void> {
    if (!this.worldTerrain) {
      this.worldTerrain = await Cesium.createWorldTerrainAsync({
        requestVertexNormals: true,
        requestWaterMask: true,
      });
    }
    this.viewer.scene.terrainProvider = this.worldTerrain;

    if (this.viewer.imageryLayers.length === 0) {
      const imagery = await Cesium.IonImageryProvider.fromAssetId(2);
      this.viewer.imageryLayers.addImageryProvider(imagery);
    }

    if (!this.osmBuildings) {
      this.osmBuildings = await Cesium.createOsmBuildingsAsync();
      this.viewer.scene.primitives.add(this.osmBuildings);
    }
  }

  async setMode(mode: SceneMode): Promise<void> {
    if (mode === 'terrain') {
      await this.ensureTerrainMode();
    }
    this.applyMode(mode);
  }

  private applyMode(mode: SceneMode): void {
    this.mode = mode;
    const photorealOn = mode === 'photoreal';

    if (this.photoreal) this.photoreal.show = photorealOn;
    if (this.osmBuildings) this.osmBuildings.show = !photorealOn;

    // In photoreal mode the tiles are the surface, so hide the globe to avoid
    // z-fighting. In terrain mode the globe (with world terrain) is the surface.
    this.viewer.scene.globe.show = !photorealOn;
    this.viewer.scene.requestRender();
  }

  getMode(): SceneMode {
    return this.mode;
  }

  flyToPlace(place: Place, duration = 3.4): void {
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(place.lon, place.lat, place.height),
      orientation: {
        heading: toRad(place.heading),
        pitch: toRad(place.pitch),
        roll: 0,
      },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  /** Frame the whole planet. Duration 0 snaps instantly (used on boot). */
  flyWholePlanet(duration = 0): void {
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(-30, 25, 24_000_000),
      orientation: {
        heading: 0,
        pitch: toRad(-90),
        roll: 0,
      },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  async search(query: string): Promise<SearchResult[]> {
    if (!this.geocoder) {
      this.geocoder = new Cesium.IonGeocoderService({ scene: this.viewer.scene });
    }
    const results = await this.geocoder.geocode(query.trim());
    return results.map((r) => ({
      displayName: r.displayName,
      destination: r.destination,
    }));
  }

  flyToDestination(destination: Cesium.Cartesian3 | Cesium.Rectangle): void {
    if (destination instanceof Cesium.Rectangle) {
      // Approach the region at a shallow, cinematic angle rather than straight down.
      const center = Cesium.Rectangle.center(destination);
      const lon = Cesium.Math.toDegrees(center.longitude);
      const lat = Cesium.Math.toDegrees(center.latitude);
      const diag = Cesium.Cartesian3.distance(
        Cesium.Cartographic.toCartesian(Cesium.Rectangle.northeast(destination)),
        Cesium.Cartographic.toCartesian(Cesium.Rectangle.southwest(destination)),
      );
      const height = Cesium.Math.clamp(diag * 0.9, 600, 4_000_000);
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(lon, lat, height),
        orientation: { heading: toRad(20), pitch: toRad(-35), roll: 0 },
        duration: 3.2,
        easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
      });
    } else {
      this.viewer.camera.flyTo({
        destination,
        duration: 3.2,
        easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
      });
    }
  }

  destroy(): void {
    if (!this.viewer.isDestroyed()) this.viewer.destroy();
  }
}
