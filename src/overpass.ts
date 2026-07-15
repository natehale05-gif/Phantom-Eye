/**
 * Shared Overpass (OpenStreetMap) query helper used by street labels, trail
 * layers, and nearby search.
 *
 * Public Overpass mirrors are unreliable: the main instance frequently returns
 * 504s under load, and several "mirrors" are so slow (60s+) they always hit our
 * abort timeout. So instead of trying endpoints one-by-one, we fire the fast,
 * CORS-enabled, global mirrors in PARALLEL and take the first successful
 * response (Promise.any). If a mirror 504s or is slow, another usually answers
 * in a couple of seconds.
 */

// Fast, CORS-enabled, whole-planet mirrors (measured from the browser).
// (Region-limited instances like overpass.osm.ch are excluded — they return
// empty results outside their coverage area.)
const ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

export interface OverpassResult<T> {
  elements?: T[];
}

/**
 * Run an Overpass QL query, racing the mirrors. Resolves with the parsed JSON,
 * or null if every mirror failed/timed out.
 */
export async function overpassQuery<T>(query: string, timeoutMs = 25000): Promise<OverpassResult<T> | null> {
  const attempts = ENDPOINTS.map((endpoint) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    return fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `data=${encodeURIComponent(query)}`,
      signal: controller.signal,
    }).then(
      async (res) => {
        clearTimeout(timer);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return (await res.json()) as OverpassResult<T>;
      },
      (err) => {
        clearTimeout(timer);
        throw err;
      },
    );
  });
  try {
    return await Promise.any(attempts);
  } catch {
    return null;
  }
}
