/**
 * Cesium ion access token handling.
 *
 * The token is resolved in this order (first non-empty wins):
 *  1. A token entered at runtime in the onboarding screen (localStorage).
 *  2. A build-time token from `.env`: VITE_CESIUM_ION_TOKEN=...
 *  3. The bundled DEFAULT_TOKEN below.
 *
 * NOTE: DEFAULT_TOKEN ships in the client bundle, so it is publicly visible.
 * Scope it in Cesium ion (restrict to the assets you use and allow only your
 * deployment domain) so an exposed token cannot be misused.
 */

const STORAGE_KEY = 'phantom-eye.cesium-ion-token';

// Baked-in Cesium ion token so the app works out of the box (e.g. on GitHub
// Pages) without onboarding. A runtime or env token still overrides it.
const DEFAULT_TOKEN =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiI0MDVhOGYxMy1kMWUxLTQwMzItYjUxYS0wOTE1MDA3NDk0NjIiLCJpZCI6NDM1MzM1LCJzdWIiOiJOSDEwMTIiLCJpc3MiOiJodHRwczovL2FwaS5jZXNpdW0uY29tIiwiYXVkIjoiUGhhbnRvbSBFeWUiLCJpYXQiOjE3Nzk1NjM2NDR9.RPB9Y2iSYN26R4GhjBxooUNLq7U_36bkW0mGaWL9peI';

const ENV_TOKEN = (import.meta.env.VITE_CESIUM_ION_TOKEN ?? DEFAULT_TOKEN).trim();

export function getStoredToken(): string {
  try {
    return (localStorage.getItem(STORAGE_KEY) ?? '').trim();
  } catch {
    return '';
  }
}

export function setStoredToken(token: string): void {
  try {
    localStorage.setItem(STORAGE_KEY, token.trim());
  } catch {
    /* ignore private-mode storage failures */
  }
}

export function clearStoredToken(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* ignore */
  }
}

/** Returns the active token, preferring a runtime-entered one over the env value. */
export function getActiveToken(): string {
  return getStoredToken() || ENV_TOKEN;
}

export function hasToken(): boolean {
  return getActiveToken().length > 0;
}
