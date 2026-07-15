import type { LngLat } from './geo';

/**
 * Place search powered by Photon (photon.komoot.io) — a keyless, CORS-enabled
 * geocoder built on OpenStreetMap. It resolves addresses, cities, and points of
 * interest (restaurants, shops, parks, trailheads, …), so you can navigate to
 * anywhere Apple Maps could take you. Results can be biased toward a location.
 */

export type OsmType = 'node' | 'way' | 'relation';

/** Extra Apple-Maps-style details for a place (may be loaded lazily). */
export interface PlaceDetails {
  osmType?: OsmType;
  osmId?: number;
  phone?: string;
  website?: string;
  openingHours?: string;
  address?: string;
}

export interface PlaceResult extends PlaceDetails {
  name: string;
  detail: string;
  lon: number;
  lat: number;
  category: string;
  /** Category chip id (food, hotels, …) when this came from a category search. */
  categoryId?: string;
}

interface PhotonProps {
  name?: string;
  housenumber?: string;
  street?: string;
  locality?: string;
  district?: string;
  city?: string;
  county?: string;
  state?: string;
  country?: string;
  postcode?: string;
  osm_key?: string;
  osm_value?: string;
  osm_type?: string;
  osm_id?: number;
}

const OSM_TYPE: Record<string, OsmType> = { N: 'node', W: 'way', R: 'relation' };

export async function searchPlaces(query: string, near?: LngLat | null): Promise<PlaceResult[]> {
  const q = query.trim();
  if (q.length < 2) return [];

  const params = new URLSearchParams({ q, limit: '7', lang: 'en' });
  if (near) {
    params.set('lat', String(near[1]));
    params.set('lon', String(near[0]));
  }
  const res = await fetch(`https://photon.komoot.io/api/?${params.toString()}`);
  if (!res.ok) throw new Error(`Search failed (${res.status})`);
  const data = await res.json();

  const out: PlaceResult[] = [];
  const seen = new Set<string>();
  for (const f of data.features ?? []) {
    const coords = f.geometry?.coordinates;
    if (!coords || coords.length < 2) continue;
    const props: PhotonProps = f.properties ?? {};
    const name = displayName(props);
    if (!name) continue;
    const key = `${name}@${coords[0].toFixed(4)},${coords[1].toFixed(4)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      name,
      detail: detailLine(props, name),
      lon: coords[0],
      lat: coords[1],
      category: props.osm_value ?? props.osm_key ?? '',
      osmType: props.osm_type ? OSM_TYPE[props.osm_type] : undefined,
      osmId: props.osm_id,
      address: addressLine(props),
    });
  }
  return out;
}

function displayName(p: PhotonProps): string {
  if (p.name) return p.name;
  if (p.street) return p.housenumber ? `${p.housenumber} ${p.street}` : p.street;
  return p.city ?? p.state ?? p.country ?? '';
}

function addressLine(p: PhotonProps): string {
  const street = p.housenumber && p.street ? `${p.housenumber} ${p.street}` : p.street;
  const cityLine = [p.city ?? p.locality, p.state, p.postcode].filter(Boolean).join(', ');
  return [street, cityLine].filter(Boolean).join(', ');
}

function detailLine(p: PhotonProps, name: string): string {
  const parts: string[] = [];
  const streetLine = p.housenumber && p.street ? `${p.housenumber} ${p.street}` : p.street;
  if (streetLine && streetLine !== name) parts.push(streetLine);
  const town = p.city ?? p.locality ?? p.county;
  if (town && town !== name) parts.push(town);
  if (p.state && p.state !== name && p.state !== town) parts.push(p.state);
  if (parts.length === 0 && p.country) parts.push(p.country);
  return parts.join(', ');
}
