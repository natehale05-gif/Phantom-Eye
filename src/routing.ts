/**
 * Turn-by-turn routing via the public OSRM demo server (no API key needed).
 *
 * Returns the route geometry plus human-readable maneuver steps. This is a
 * free, rate-limited demo service — fine for exploring, not for production
 * traffic. Swap in a keyed provider (OpenRouteService, Mapbox, etc.) later if
 * you need reliability or traffic.
 */

import type { LngLat } from './geo';
export type { LngLat };

export type ManeuverKind =
  | 'depart'
  | 'straight'
  | 'left'
  | 'slight-left'
  | 'sharp-left'
  | 'right'
  | 'slight-right'
  | 'sharp-right'
  | 'uturn'
  | 'roundabout'
  | 'merge'
  | 'ramp'
  | 'arrive';

export interface RouteStep {
  instruction: string;
  distance: number; // meters to travel during this step
  location: LngLat; // where the maneuver happens
  kind: ManeuverKind;
}

export interface Route {
  coordinates: LngLat[]; // full geometry, [lon, lat]
  steps: RouteStep[];
  distance: number; // meters
  duration: number; // seconds
}

export type TravelMode = 'driving' | 'walking' | 'cycling';

/**
 * Average speeds (m/s) used to estimate walking/cycling time. The public OSRM
 * demo only serves the driving network, so for walk/cycle we reuse the road
 * geometry and estimate duration from distance — good enough to explore with.
 */
const MODE_SPEED: Record<TravelMode, number> = {
  driving: 0, // 0 = use OSRM's own duration
  walking: 1.4, // ~5 km/h
  cycling: 4.2, // ~15 km/h
};

/** Duration (seconds) for a route travelled in the given mode. */
export function durationForMode(route: Route, mode: TravelMode): number {
  const speed = MODE_SPEED[mode];
  return speed > 0 ? route.distance / speed : route.duration;
}

/**
 * Fetch one or more candidate routes (the first is the primary; the rest are
 * alternates, Apple-Maps style). Driving geometry from the OSRM demo server.
 */
export async function fetchRoutes(start: LngLat, end: LngLat): Promise<Route[]> {
  const coords = `${start[0]},${start[1]};${end[0]},${end[1]}`;
  const url =
    `https://router.project-osrm.org/route/v1/driving/${coords}` +
    `?overview=full&geometries=geojson&steps=true&alternatives=3`;

  const res = await fetch(url);
  if (!res.ok) throw new Error(`Routing failed (${res.status})`);
  const data = await res.json();
  if (data.code !== 'Ok' || !data.routes?.length) {
    throw new Error('No route found');
  }
  return data.routes.map(parseRoute);
}

/** Backwards-compatible single-route fetch. */
export async function fetchRoute(start: LngLat, end: LngLat): Promise<Route> {
  return (await fetchRoutes(start, end))[0];
}

interface OsrmRoute {
  geometry: { coordinates: LngLat[] };
  legs?: { steps?: { name?: string; distance?: number; maneuver: { type?: string; modifier?: string; location: LngLat } }[] }[];
  distance?: number;
  duration?: number;
}

function parseRoute(route: OsrmRoute): Route {
  const coordinates: LngLat[] = route.geometry.coordinates;
  const steps: RouteStep[] = [];
  for (const leg of route.legs ?? []) {
    for (const step of leg.steps ?? []) {
      const kind = classify(step.maneuver);
      steps.push({
        instruction: describe(step.name, kind),
        distance: step.distance ?? 0,
        location: step.maneuver.location as LngLat,
        kind,
      });
    }
  }
  return {
    coordinates,
    steps,
    distance: route.distance ?? 0,
    duration: route.duration ?? 0,
  };
}

function classify(m: { type?: string; modifier?: string }): ManeuverKind {
  const type = m.type ?? '';
  const mod = m.modifier ?? '';
  if (type === 'depart') return 'depart';
  if (type === 'arrive') return 'arrive';
  if (type === 'roundabout' || type === 'rotary') return 'roundabout';
  if (type === 'merge') return 'merge';
  if (type === 'on ramp' || type === 'off ramp') return 'ramp';
  if (mod.includes('uturn')) return 'uturn';
  if (mod === 'left') return 'left';
  if (mod === 'right') return 'right';
  if (mod === 'slight left') return 'slight-left';
  if (mod === 'slight right') return 'slight-right';
  if (mod === 'sharp left') return 'sharp-left';
  if (mod === 'sharp right') return 'sharp-right';
  return 'straight';
}

function describe(name: string | undefined, kind: ManeuverKind): string {
  const road = name && name.trim() ? name.trim() : '';
  const onto = road ? ` onto ${road}` : '';
  const on = road ? ` on ${road}` : '';

  switch (kind) {
    case 'depart':
      return road ? `Head out on ${road}` : 'Start';
    case 'arrive':
      return 'Arrive at your destination';
    case 'roundabout':
      return `Enter the roundabout${onto}`;
    case 'merge':
      return `Merge${onto}`;
    case 'ramp':
      return `Take the ramp${onto}`;
    case 'uturn':
      return `Make a U-turn${on}`;
    case 'left':
      return `Turn left${onto}`;
    case 'right':
      return `Turn right${onto}`;
    case 'slight-left':
      return `Slight left${onto}`;
    case 'slight-right':
      return `Slight right${onto}`;
    case 'sharp-left':
      return `Sharp left${onto}`;
    case 'sharp-right':
      return `Sharp right${onto}`;
    default:
      return road ? `Continue on ${road}` : 'Continue straight';
  }
}

/** Great-circle distance in meters between two [lon, lat] points. */
export function haversine(a: LngLat, b: LngLat): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b[1] - a[1]);
  const dLon = toRad(b[0] - a[0]);
  const lat1 = toRad(a[1]);
  const lat2 = toRad(b[1]);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** US-friendly imperial distance formatting. */
export function formatDistance(meters: number): string {
  const feet = meters * 3.28084;
  if (feet < 1000) return `${Math.round(feet / 10) * 10} ft`;
  const miles = meters / 1609.344;
  return `${miles.toFixed(miles < 10 ? 1 : 0)} mi`;
}

export function formatDuration(seconds: number): string {
  const min = Math.round(seconds / 60);
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} hr ${m} min` : `${h} hr`;
}
