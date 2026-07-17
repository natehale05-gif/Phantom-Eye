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
 * Start watching position. Returns a stop function. High-accuracy mode forces
 * a fresh GPS reading on every poll (`maximumAge: 0`) — needed while actively
 * navigating or recording a track, but a real drain on the radio/battery (and
 * a heat source, since each fix can force a camera-follow re-render) if left
 * on indefinitely just for casual "where am I" use. The low-accuracy mode
 * accepts a fix up to 15s old, which is plenty for following along at a walk
 * or drive without demanding a brand-new radio read every time.
 */
export function watchFixes(
  onFix: (fix: Fix) => void,
  onError?: (err: GeolocationPositionError) => void,
  opts?: { highAccuracy?: boolean },
): () => void {
  if (!('geolocation' in navigator)) {
    onError?.({ code: 2, message: 'unsupported' } as GeolocationPositionError);
    return () => {};
  }
  const highAccuracy = opts?.highAccuracy ?? true;
  const id = navigator.geolocation.watchPosition((p) => onFix(toFix(p)), onError, {
    enableHighAccuracy: highAccuracy,
    timeout: 20000,
    maximumAge: highAccuracy ? 0 : 15000,
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
