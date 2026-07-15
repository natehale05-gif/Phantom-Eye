import type { Globe } from './globe';
import type { Shell } from './ui';
import { toast } from './navigation';

/**
 * Offline support. A service worker precaches the app shell and runtime-caches
 * map *data* (OSM raster tiles, geocoding, routing, weather) so the app opens
 * and stays useful with no signal — Apple-Maps-style "downloaded areas".
 *
 * Note: Google's Photorealistic 3D Tiles may not be stored offline under their
 * license, so offline falls back to the cached 2D OpenStreetMap surface (which
 * includes street names). We deliberately never cache Google/Cesium tile hosts.
 */

const MAP_CACHE = 'nomos-map-v1';
const OSM_TILE = 'https://tile.openstreetmap.org';

export function registerServiceWorker(): void {
  if (!('serviceWorker' in navigator)) return;
  // Skip in dev so it never interferes with Vite HMR.
  if (import.meta.env.DEV) return;
  window.addEventListener('load', () => {
    const url = new URL('sw.js', document.baseURI).href;
    navigator.serviceWorker.register(url).catch(() => {
      /* offline support is progressive enhancement */
    });
  });
}

function lon2tile(lon: number, z: number): number {
  return Math.floor(((lon + 180) / 360) * 2 ** z);
}

function lat2tile(lat: number, z: number): number {
  const r = (lat * Math.PI) / 180;
  return Math.floor(((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * 2 ** z);
}

/** Roughly map a view span (degrees of longitude) to a sensible OSM zoom. */
function baseZoomFor(spanDeg: number): number {
  const z = Math.round(Math.log2(360 / Math.max(spanDeg, 1e-4)));
  return Math.max(3, Math.min(17, z));
}

/**
 * Pre-cache the OSM raster tiles covering the current view (a few zoom levels)
 * so the region can be browsed offline. Capped so a single download stays
 * polite to the OSM tile servers.
 */
export async function downloadCurrentArea(shell: Shell, globe: Globe): Promise<void> {
  const b = globe.viewBoundsDeg();
  if (!b) {
    toast(shell, 'Move closer to an area to download it');
    return;
  }
  const span = Math.max(b.east - b.west, b.north - b.south);
  if (span > 4) {
    toast(shell, 'Zoom in to download a smaller area');
    return;
  }
  if (!('caches' in window)) {
    toast(shell, 'Offline storage not available');
    return;
  }

  const z0 = baseZoomFor(b.east - b.west);
  const levels = [z0, z0 + 1, z0 + 2].filter((z) => z <= 18);
  const urls: string[] = [];
  const MAX_TILES = 500;
  for (const z of levels) {
    const xMin = lon2tile(b.west, z);
    const xMax = lon2tile(b.east, z);
    const yMin = lat2tile(b.north, z);
    const yMax = lat2tile(b.south, z);
    for (let x = xMin; x <= xMax; x++) {
      for (let y = yMin; y <= yMax; y++) {
        urls.push(`${OSM_TILE}/${z}/${x}/${y}.png`);
        if (urls.length >= MAX_TILES) break;
      }
      if (urls.length >= MAX_TILES) break;
    }
    if (urls.length >= MAX_TILES) break;
  }

  if (!urls.length) {
    toast(shell, 'Nothing to download here');
    return;
  }

  toast(shell, `Downloading ${urls.length} map tiles…`);
  const cache = await caches.open(MAP_CACHE);
  let ok = 0;
  const CONCURRENCY = 6;
  let i = 0;
  async function worker(): Promise<void> {
    while (i < urls.length) {
      const url = urls[i++];
      try {
        const res = await fetch(url, { mode: 'cors' });
        if (res.ok) {
          await cache.put(url, res.clone());
          ok++;
        }
      } catch {
        /* skip tiles that fail; keep going */
      }
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  toast(
    shell,
    ok ? `Area downloaded (${ok} tiles) — available offline` : 'Download failed — check connection',
  );
}
