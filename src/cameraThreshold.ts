import type * as Cesium from 'cesium';

/**
 * `Cesium.Camera.percentageChanged` is a single shared knob — the compass,
 * street labels, and trail layers each want their own "changed" threshold, but
 * whichever feature sets it last silently overrides everyone else's. This
 * keeps the effective value at the minimum (most sensitive) threshold any
 * currently-active feature actually needs.
 */

const registry = new WeakMap<Cesium.Viewer, Map<string, number>>();

export function requireCameraPercentageChanged(viewer: Cesium.Viewer, key: string, value: number): void {
  const thresholds = registry.get(viewer) ?? new Map<string, number>();
  thresholds.set(key, value);
  registry.set(viewer, thresholds);
  viewer.camera.percentageChanged = Math.min(...thresholds.values());
}

export function releaseCameraPercentageChanged(viewer: Cesium.Viewer, key: string): void {
  const thresholds = registry.get(viewer);
  if (!thresholds) return;
  thresholds.delete(key);
  viewer.camera.percentageChanged = thresholds.size ? Math.min(...thresholds.values()) : 0.05;
}
