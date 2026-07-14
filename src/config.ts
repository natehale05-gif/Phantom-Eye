/**
 * Cesium ion access token handling.
 *
 * The token can be provided two ways:
 *  1. At build time via a `.env` file:  VITE_CESIUM_ION_TOKEN=...
 *  2. At runtime, entered by the user in the onboarding screen and persisted
 *     to localStorage. This lets anyone bring their own key without a rebuild.
 *
 * Runtime entry always wins so a user can override a baked-in token.
 */

const STORAGE_KEY = 'phantom-eye.cesium-ion-token';

const ENV_TOKEN = (import.meta.env.VITE_CESIUM_ION_TOKEN ?? '').trim();

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
