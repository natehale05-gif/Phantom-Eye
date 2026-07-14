import * as Cesium from 'cesium';

/** Cesium ion asset ID for Google Photorealistic 3D Tiles (photoreal buildings + terrain). */
const GOOGLE_PHOTOREAL_ASSET_ID = 2275207;

export type SceneMode = 'photoreal' | 'terrain';

const toRad = Cesium.Math.toRadians;

export class Globe {
  readonly viewer: Cesium.Viewer;
  private photoreal?: Cesium.Cesium3DTileset;
  private osmBuildings?: Cesium.Cesium3DTileset;
  private worldTerrain?: Cesium.TerrainProvider;
  private geocoder?: Cesium.IonGeocoderService;
  private mode: SceneMode = 'photoreal';
  private token = '';

  constructor(container: HTMLElement, creditContainer: HTMLElement) {
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
    this.flyWholePlanet(0);
  }

  private tuneScene(): void {
    const { scene } = this.viewer;
    if (scene.skyAtmosphere) scene.skyAtmosphere.show = true;
    scene.fog.enabled = true;
    scene.fog.density = 0.0002;
    scene.globe.enableLighting = true;
    scene.globe.showGroundAtmosphere = true;
    scene.globe.baseColor = Cesium.Color.fromCssColorString('#05080f');
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

  /** Sets (or replaces) the Cesium ion token and loads the photoreal surface. */
  async setToken(token: string): Promise<void> {
    const trimmed = token.trim();
    if (trimmed === this.token && this.photoreal) return;
    this.token = trimmed;
    Cesium.Ion.defaultAccessToken = trimmed;
    await this.initPhotoreal();
  }

  private async initPhotoreal(): Promise<void> {
    if (this.photoreal) {
      this.viewer.scene.primitives.remove(this.photoreal);
      this.photoreal = undefined;
    }
    this.photoreal = await Cesium.Cesium3DTileset.fromIonAssetId(
      GOOGLE_PHOTOREAL_ASSET_ID,
      { maximumScreenSpaceError: 12 },
    );
    this.viewer.scene.primitives.add(this.photoreal);
    this.applyMode(this.mode);
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
    if (mode === 'terrain') await this.ensureTerrainMode();
    this.applyMode(mode);
  }

  private applyMode(mode: SceneMode): void {
    this.mode = mode;
    const photorealOn = mode === 'photoreal';
    if (this.photoreal) this.photoreal.show = photorealOn;
    if (this.osmBuildings) this.osmBuildings.show = !photorealOn;
    this.viewer.scene.globe.show = !photorealOn;
    this.viewer.scene.requestRender();
  }

  getMode(): SceneMode {
    return this.mode;
  }

  flyTo(
    lon: number,
    lat: number,
    height: number,
    heading = 0,
    pitch = -30,
    duration = 3.2,
  ): void {
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lon, lat, height),
      orientation: { heading: toRad(heading), pitch: toRad(pitch), roll: 0 },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  flyWholePlanet(duration = 2.4): void {
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(-30, 25, 24_000_000),
      orientation: { heading: 0, pitch: toRad(-90), roll: 0 },
      duration,
      easingFunction: Cesium.EasingFunction.QUINTIC_IN_OUT,
    });
  }

  async search(query: string): Promise<{ displayName: string; lon: number; lat: number; height: number }[]> {
    if (!this.geocoder) {
      this.geocoder = new Cesium.IonGeocoderService({ scene: this.viewer.scene });
    }
    const results = await this.geocoder.geocode(query.trim());
    return results.map((r) => {
      const { destination } = r;
      if (destination instanceof Cesium.Rectangle) {
        const center = Cesium.Rectangle.center(destination);
        const diag = Cesium.Cartesian3.distance(
          Cesium.Cartographic.toCartesian(Cesium.Rectangle.northeast(destination)),
          Cesium.Cartographic.toCartesian(Cesium.Rectangle.southwest(destination)),
        );
        return {
          displayName: r.displayName,
          lon: Cesium.Math.toDegrees(center.longitude),
          lat: Cesium.Math.toDegrees(center.latitude),
          height: Cesium.Math.clamp(diag * 0.9, 600, 4_000_000),
        };
      }
      const carto = Cesium.Cartographic.fromCartesian(destination);
      return {
        displayName: r.displayName,
        lon: Cesium.Math.toDegrees(carto.longitude),
        lat: Cesium.Math.toDegrees(carto.latitude),
        height: Math.max(carto.height + 1500, 1500),
      };
    });
  }
}
