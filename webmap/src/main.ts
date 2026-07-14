import { Globe, type SceneMode } from './globe';

/**
 * Emit an event to the Flutter host (via the flutter_inappwebview bridge) and
 * also as a DOM CustomEvent so the page can be exercised in a plain browser.
 */
function emit(event: string, data: Record<string, unknown> = {}): void {
  const w = window as unknown as {
    flutter_inappwebview?: { callHandler: (name: string, ...args: unknown[]) => unknown };
  };
  try {
    w.flutter_inappwebview?.callHandler('phantomEye', event, data);
  } catch {
    /* not running inside the app */
  }
  window.dispatchEvent(new CustomEvent(`pe:${event}`, { detail: data }));
}

function classifyError(err: unknown): 'token' | 'network' | 'other' {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'network';
  const msg = String((err as { message?: string })?.message ?? err ?? '').toLowerCase();
  if (msg.includes('401') || msg.includes('403') || msg.includes('token') || msg.includes('unauthorized')) {
    return 'token';
  }
  if (msg.includes('network') || msg.includes('fetch') || msg.includes('failed to load')) {
    return 'network';
  }
  return 'other';
}

const container = document.getElementById('cesiumContainer')!;
const credits = document.getElementById('peCredits')!;

let globe: Globe | null = null;
let lastResults: { displayName: string; lon: number; lat: number; height: number }[] = [];

function ensureGlobe(): Globe {
  if (!globe) globe = new Globe(container, credits);
  return globe;
}

const api = {
  async setToken(token: string): Promise<void> {
    try {
      emit('loading', { on: true, label: 'Loading photoreal tiles' });
      await ensureGlobe().setToken(token);
      emit('loading', { on: false });
      emit('ready', {});
    } catch (err) {
      emit('loading', { on: false });
      emit('error', { kind: classifyError(err), message: String(err) });
    }
  },

  async setMode(mode: SceneMode): Promise<void> {
    try {
      if (mode === 'terrain') emit('loading', { on: true, label: 'Loading world terrain' });
      await ensureGlobe().setMode(mode);
      emit('loading', { on: false });
      emit('modeChanged', { mode });
    } catch (err) {
      emit('loading', { on: false });
      emit('error', { kind: classifyError(err), message: String(err) });
    }
  },

  flyTo(lon: number, lat: number, height: number, heading = 0, pitch = -30, duration = 3.2): void {
    ensureGlobe().flyTo(lon, lat, height, heading, pitch, duration);
  },

  flyHome(duration = 2.4): void {
    ensureGlobe().flyWholePlanet(duration);
  },

  async search(query: string): Promise<void> {
    try {
      lastResults = await ensureGlobe().search(query);
      emit('searchResults', { query, items: lastResults });
    } catch (err) {
      lastResults = [];
      emit('searchResults', { query, items: [] });
      emit('error', { kind: classifyError(err), message: String(err) });
    }
  },

  flyToSearchResult(index: number): void {
    const r = lastResults[index];
    if (!r) return;
    ensureGlobe().flyTo(r.lon, r.lat, r.height, 20, -35, 3.2);
  },
};

// Expose the API to the Flutter host and to page scripts.
(window as unknown as { PE: typeof api }).PE = api;

// Let the host know the page (not yet the globe) is ready to receive a token.
window.addEventListener('load', () => emit('pageReady', {}));
