import type { LngLat } from './geo';
import type { PlaceResult } from './geocode';
import type { Category } from './categories';
import { haversine } from './routing';

/**
 * "Find nearby" search for a category (restaurants, hotels, gas, …) using the
 * Overpass API over OpenStreetMap data. Overpass is keyless and CORS-enabled,
 * and unlike a text geocoder it can answer "what's around this point", which is
 * exactly what the category chips need — just like Apple Maps' nearby search.
 */

const ENDPOINT = 'https://overpass-api.de/api/interpreter';
const RADIUS_M = 3000;
const MAX_RESULTS = 18;

interface OverpassElement {
  type: string;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
}

export async function searchNearby(cat: Category, near: LngLat): Promise<PlaceResult[]> {
  const [lon, lat] = near;
  const clauses = cat.osm
    .map(
      ([k, v]) =>
        `node["${k}"="${v}"](around:${RADIUS_M},${lat},${lon});` +
        `way["${k}"="${v}"](around:${RADIUS_M},${lat},${lon});`,
    )
    .join('');
  const query = `[out:json][timeout:20];(${clauses});out center ${MAX_RESULTS * 3};`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  let data: { elements?: OverpassElement[] };
  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      body: `data=${encodeURIComponent(query)}`,
      signal: controller.signal,
    });
    if (!res.ok) throw new Error(`Nearby search failed (${res.status})`);
    data = await res.json();
  } finally {
    clearTimeout(timer);
  }

  const out: PlaceResult[] = [];
  const seen = new Set<string>();
  for (const el of data.elements ?? []) {
    const tags = el.tags ?? {};
    const name = tags.name;
    if (!name) continue;
    const p = el.center ?? (el.lat != null && el.lon != null ? { lat: el.lat, lon: el.lon } : null);
    if (!p) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      name,
      detail: detailLine(tags),
      lon: p.lon,
      lat: p.lat,
      category: cat.label,
      categoryId: cat.id,
    });
  }

  out.sort((a, b) => haversine(near, [a.lon, a.lat]) - haversine(near, [b.lon, b.lat]));
  return out.slice(0, MAX_RESULTS);
}

function detailLine(tags: Record<string, string>): string {
  const street =
    tags['addr:housenumber'] && tags['addr:street']
      ? `${tags['addr:housenumber']} ${tags['addr:street']}`
      : tags['addr:street'];
  const bits = [street, tags['addr:city'], tags.cuisine?.replace(/_/g, ' ')].filter(Boolean);
  return bits.slice(0, 2).join(' · ');
}
