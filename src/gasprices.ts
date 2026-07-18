/**
 * Local gas price tracker. There's no free, keyless API for live per-station
 * fuel prices, so — like the earliest days of GasBuddy/Waze — Phantom Eye
 * tracks what you report: enter the price you see at the pump on a gas
 * station's place card, and it's remembered (in this browser) and shown the
 * next time you look that station up, by tap or by search.
 */

export interface GasPriceReport {
  price: number;
  reportedAt: string;
}

interface GasStationRef {
  osmType?: 'node' | 'way' | 'relation';
  osmId?: number;
  name: string;
  lat: number;
  lon: number;
}

const STORAGE_KEY = 'phantom-eye.gasPrices';

function stationKey(place: GasStationRef): string {
  if (place.osmType && place.osmId != null) return `${place.osmType}/${place.osmId}`;
  return `${place.name.toLowerCase()}@${place.lat.toFixed(4)},${place.lon.toFixed(4)}`;
}

// Cached in memory after the first load so repeated getGasPrice() calls
// (one per place-card render) don't re-parse the whole localStorage blob
// every time. reportGasPrice() mutates and writes through this same object,
// so it stays in sync without any extra invalidation.
let cached: Record<string, GasPriceReport> | null = null;

function loadAll(): Record<string, GasPriceReport> {
  if (cached) return cached;
  let parsed: Record<string, GasPriceReport> = {};
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) parsed = JSON.parse(raw);
  } catch {
    parsed = {};
  }
  cached = parsed;
  return cached;
}

export function getGasPrice(place: GasStationRef): GasPriceReport | null {
  return loadAll()[stationKey(place)] ?? null;
}

export function reportGasPrice(place: GasStationRef, price: number): GasPriceReport {
  const report: GasPriceReport = { price, reportedAt: new Date().toISOString() };
  const all = loadAll();
  all[stationKey(place)] = report;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(all));
  } catch {
    /* private-mode storage failure — report still reflects this session */
  }
  return report;
}

export function formatPrice(price: number): string {
  return `$${price.toFixed(2)}/gal`;
}

export function formatRelativeTime(iso: string): string {
  const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} hr${hours === 1 ? '' : 's'} ago`;
  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? '' : 's'} ago`;
}
