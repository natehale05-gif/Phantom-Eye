import type { LngLat } from './geo';
import type { PlaceResult, PlaceDetails, OsmType } from './geocode';
import type { Category } from './categories';
import { haversine } from './routing';
import { overpassQuery } from './overpass';

/**
 * "Find nearby" search for a category (restaurants, hotels, gas, …) using the
 * Overpass API over OpenStreetMap data. Overpass is keyless and CORS-enabled,
 * and unlike a text geocoder it can answer "what's around this point", which is
 * exactly what the category chips need — just like Apple Maps' nearby search.
 */

const RADIUS_M = 3000;
const MAX_RESULTS = 18;

interface OverpassElement {
  type: string;
  id?: number;
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
  const data = await fetchOverpass(query);

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
      osmType: el.type as OsmType,
      osmId: typeof el.id === 'number' ? el.id : undefined,
      ...tagsToDetails(tags),
    });
  }

  out.sort((a, b) => haversine(near, [a.lon, a.lat]) - haversine(near, [b.lon, b.lat]));
  return out.slice(0, MAX_RESULTS);
}

async function fetchOverpass(query: string): Promise<{ elements?: OverpassElement[] }> {
  const data = await overpassQuery<OverpassElement>(query);
  if (!data) throw new Error('Nearby search failed');
  return data;
}

function detailLine(tags: Record<string, string>): string {
  const street =
    tags['addr:housenumber'] && tags['addr:street']
      ? `${tags['addr:housenumber']} ${tags['addr:street']}`
      : tags['addr:street'];
  const bits = [street, tags['addr:city'], tags.cuisine?.replace(/_/g, ' ')].filter(Boolean);
  return bits.slice(0, 2).join(' · ');
}

/** Extra place details (hours, phone, website, address) from OSM tags. */
function tagsToDetails(tags: Record<string, string>): PlaceDetails {
  const street =
    tags['addr:housenumber'] && tags['addr:street']
      ? `${tags['addr:housenumber']} ${tags['addr:street']}`
      : tags['addr:street'];
  const address = [street, tags['addr:city'], tags['addr:state'], tags['addr:postcode']]
    .filter(Boolean)
    .join(', ');
  return {
    phone: tags.phone ?? tags['contact:phone'],
    website: tags.website ?? tags['contact:website'] ?? tags.url,
    openingHours: tags.opening_hours,
    address: address || undefined,
  };
}

/**
 * Fetch full details (hours, phone, website, address) for a single OSM element,
 * used to enrich a place card for results that arrived without them (e.g. from
 * the text geocoder).
 */
export async function fetchPlaceDetails(osmType: OsmType, osmId: number): Promise<PlaceDetails> {
  const query = `[out:json][timeout:15];${osmType}(${osmId});out tags;`;
  const data = await fetchOverpass(query);
  const tags = data.elements?.[0]?.tags;
  return tags ? tagsToDetails(tags) : {};
}
