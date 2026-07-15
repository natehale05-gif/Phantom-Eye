import type { LngLat } from './geo';

export interface Fix {
  lonlat: LngLat;
  accuracy: number;
  heading: number | null;
  altitude: number | null;
  speed: number | null;
}

function toFix(pos: GeolocationPosition): Fix {
  return {
    lonlat: [pos.coords.longitude, pos.coords.latitude],
    accuracy: pos.coords.accuracy ?? 10,
    heading: Number.isFinite(pos.coords.heading) ? (pos.coords.heading as number) : null,
    altitude: Number.isFinite(pos.coords.altitude) ? (pos.coords.altitude as number) : null,
    speed: Number.isFinite(pos.coords.speed) ? (pos.coords.speed as number) : null,
  };
}

export function getFix(): Promise<Fix> {
  return new Promise((resolve, reject) => {
    if (!('geolocation' in navigator)) {
      reject(new Error('unsupported'));
      return;
    }
    navigator.geolocation.getCurrentPosition((p) => resolve(toFix(p)), reject, {
      enableHighAccuracy: true,
      timeout: 20000,
      maximumAge: 0, // never accept a stale/cached fix — always resolve fresh GPS
    });
  });
}

/**
 * Start watching position at the highest available accuracy. Returns a stop
 * function. `maximumAge: 0` forces fresh readings so the fix keeps tightening
 * as the GPS/Wi-Fi radios settle.
 */
export function watchFixes(
  onFix: (fix: Fix) => void,
  onError?: (err: GeolocationPositionError) => void,
): () => void {
  if (!('geolocation' in navigator)) {
    onError?.({ code: 2, message: 'unsupported' } as GeolocationPositionError);
    return () => {};
  }
  const id = navigator.geolocation.watchPosition((p) => onFix(toFix(p)), onError, {
    enableHighAccuracy: true,
    timeout: 20000,
    maximumAge: 0,
  });
  return () => navigator.geolocation.clearWatch(id);
}

export function locationErrorText(err: unknown): string {
  const code = (err as GeolocationPositionError)?.code;
  if (code === 1) return 'Location permission denied.';
  if (code === 2) return 'Location unavailable.';
  if (code === 3) return 'Location request timed out.';
  return 'Could not get your location.';
}
