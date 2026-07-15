/* Nomos service worker — offline app shell + map-data caching.
 *
 * Strategy:
 *  - App shell (same-origin JS/CSS/wasm/workers/html): cache-first, so the app
 *    boots with no network once it has been visited.
 *  - Navigations: network-first, falling back to the cached page when offline.
 *  - Map DATA (OSM raster tiles, geocoding, routing, weather): stale-while-
 *    revalidate, so revisited/downloaded areas keep working offline.
 *  - Google Photorealistic 3D Tiles + Cesium ion are NEVER cached (their license
 *    forbids storing tiles), so they simply pass through to the network.
 */

const SHELL_CACHE = 'nomos-shell-v1';
const DATA_CACHE = 'nomos-data-v1';
const MAP_CACHE = 'nomos-map-v1';
const KEEP = new Set([SHELL_CACHE, DATA_CACHE, MAP_CACHE]);

// Hosts whose GET responses we may cache as map DATA.
const DATA_HOSTS = [
  'photon.komoot.io',
  'router.project-osrm.org',
  'api.open-meteo.com',
  'marine-api.open-meteo.com',
  'api.bigdatacloud.net',
];
const MAP_TILE_HOST = 'tile.openstreetmap.org';

// Hosts we must never store (licensing) — always go straight to network.
const NO_CACHE_HOSTS = [
  'tile.googleapis.com',
  'assets.ion.cesium.com',
  'api.cesium.com',
];

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(names.filter((n) => !KEEP.has(n)).map((n) => caches.delete(n)));
      await self.clients.claim();
    })(),
  );
});

function isShellAsset(url) {
  return (
    url.origin === self.location.origin &&
    /\.(js|mjs|css|wasm|json|png|jpg|jpeg|svg|gif|webp|woff2?|ttf|ico)$/i.test(url.pathname)
  );
}

async function cacheFirst(request, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(request);
  if (hit) return hit;
  const res = await fetch(request);
  if (res && (res.ok || res.type === 'opaque')) cache.put(request, res.clone());
  return res;
}

async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(request);
  const network = fetch(request)
    .then((res) => {
      if (res && res.ok) cache.put(request, res.clone());
      return res;
    })
    .catch(() => undefined);
  return hit || (await network) || Response.error();
}

async function networkFirstDoc(request) {
  const cache = await caches.open(SHELL_CACHE);
  try {
    const res = await fetch(request);
    if (res && res.ok) cache.put(request, res.clone());
    return res;
  } catch {
    const hit = (await cache.match(request)) || (await cache.match('index.html'));
    return hit || Response.error();
  }
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;

  let url;
  try {
    url = new URL(request.url);
  } catch {
    return;
  }

  if (NO_CACHE_HOSTS.includes(url.hostname)) return; // network only

  if (request.mode === 'navigate') {
    event.respondWith(networkFirstDoc(request));
    return;
  }

  if (url.hostname === MAP_TILE_HOST) {
    event.respondWith(cacheFirst(request, MAP_CACHE));
    return;
  }

  if (DATA_HOSTS.includes(url.hostname)) {
    event.respondWith(staleWhileRevalidate(request, DATA_CACHE));
    return;
  }

  if (isShellAsset(url)) {
    event.respondWith(staleWhileRevalidate(request, SHELL_CACHE));
    return;
  }
});
