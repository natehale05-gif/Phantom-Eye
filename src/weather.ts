/**
 * Weather + marine (surf) data from Open-Meteo — a free, keyless, CORS-enabled
 * API. The forecast endpoint powers the Apple-Weather-style page; the marine
 * endpoint powers the Surfline-style surf report. Reverse geocoding (for a
 * friendly place name) uses BigDataCloud's keyless client endpoint.
 */

export interface CurrentWeather {
  temp: number;
  feelsLike: number;
  code: number;
  isDay: boolean;
  humidity: number;
  pressure: number;
  windSpeed: number;
  windDir: number;
  windGust: number;
  cloud: number;
  precip: number;
  uv: number;
  visibility: number; // meters
}

export interface HourPoint {
  time: number; // epoch ms
  temp: number;
  code: number;
  isDay: boolean;
  precipProb: number;
  windSpeed: number;
}

export interface DayPoint {
  time: number;
  code: number;
  min: number;
  max: number;
  sunrise: number;
  sunset: number;
  uvMax: number;
  precipProb: number;
  windMax: number;
}

export interface WeatherData {
  lat: number;
  lon: number;
  name: string;
  current: CurrentWeather;
  hourly: HourPoint[];
  daily: DayPoint[];
  // Overall min/max across the visible days, for the 10-day range bars.
  weekMin: number;
  weekMax: number;
}

export interface SurfHour {
  time: number;
  waveHeight: number; // ft
  wavePeriod: number; // s
  swellHeight: number; // ft
  swellPeriod: number; // s
  swellDir: number;
  windSpeed: number; // mph
  windDir: number;
}

export interface SurfDay {
  time: number;
  waveMax: number;
  periodMax: number;
  dirDominant: number;
}

export interface MarineData {
  current: {
    waveHeight: number;
    wavePeriod: number;
    waveDir: number;
    swellHeight: number;
    swellPeriod: number;
    swellDir: number;
    waterTemp: number | null;
  };
  hourly: SurfHour[];
  daily: SurfDay[];
}

const FORECAST_URL = 'https://api.open-meteo.com/v1/forecast';
const MARINE_URL = 'https://marine-api.open-meteo.com/v1/marine';

/** Just enough to paint the at-a-glance weather chip. */
export async function fetchCurrentBrief(
  lat: number,
  lon: number,
): Promise<{ temp: number; code: number; isDay: boolean }> {
  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lon),
    current: 'temperature_2m,weather_code,is_day',
    temperature_unit: 'fahrenheit',
  });
  const res = await fetch(`${FORECAST_URL}?${params}`);
  if (!res.ok) throw new Error(`Weather failed (${res.status})`);
  const d = await res.json();
  return { temp: d.current.temperature_2m, code: d.current.weather_code, isDay: d.current.is_day === 1 };
}

export async function fetchWeather(lat: number, lon: number): Promise<WeatherData> {
  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lon),
    current:
      'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m',
    hourly: 'temperature_2m,weather_code,precipitation_probability,wind_speed_10m,is_day,uv_index,visibility',
    daily:
      'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max,wind_speed_10m_max',
    temperature_unit: 'fahrenheit',
    wind_speed_unit: 'mph',
    precipitation_unit: 'inch',
    timezone: 'auto',
    forecast_days: '10',
  });
  const res = await fetch(`${FORECAST_URL}?${params}`);
  if (!res.ok) throw new Error(`Weather failed (${res.status})`);
  const d = await res.json();
  const name = await reverseName(lat, lon);

  const c = d.current;
  const current: CurrentWeather = {
    temp: c.temperature_2m,
    feelsLike: c.apparent_temperature,
    code: c.weather_code,
    isDay: c.is_day === 1,
    humidity: c.relative_humidity_2m,
    pressure: c.pressure_msl,
    windSpeed: c.wind_speed_10m,
    windDir: c.wind_direction_10m,
    windGust: c.wind_gusts_10m,
    cloud: c.cloud_cover,
    precip: c.precipitation,
    uv: 0,
    visibility: 0,
  };

  const nowMs = Date.now();
  const H = d.hourly;
  const hourly: HourPoint[] = [];
  for (let i = 0; i < H.time.length; i++) {
    const t = new Date(H.time[i]).getTime();
    if (t < nowMs - 3_600_000) continue; // skip past hours
    hourly.push({
      time: t,
      temp: H.temperature_2m[i],
      code: H.weather_code[i],
      isDay: H.is_day[i] === 1,
      precipProb: H.precipitation_probability?.[i] ?? 0,
      windSpeed: H.wind_speed_10m[i],
    });
    if (hourly.length === 1) {
      current.uv = H.uv_index?.[i] ?? 0;
      current.visibility = H.visibility?.[i] ?? 0;
    }
    if (hourly.length >= 24) break;
  }

  const D = d.daily;
  const daily: DayPoint[] = D.time.map((t: string, i: number) => ({
    time: new Date(t).getTime(),
    code: D.weather_code[i],
    min: D.temperature_2m_min[i],
    max: D.temperature_2m_max[i],
    sunrise: new Date(D.sunrise[i]).getTime(),
    sunset: new Date(D.sunset[i]).getTime(),
    uvMax: D.uv_index_max?.[i] ?? 0,
    precipProb: D.precipitation_probability_max?.[i] ?? 0,
    windMax: D.wind_speed_10m_max?.[i] ?? 0,
  }));

  const weekMin = Math.min(...daily.map((x) => x.min));
  const weekMax = Math.max(...daily.map((x) => x.max));

  return { lat, lon, name, current, hourly, daily, weekMin, weekMax };
}

/** Marine/surf forecast. Throws if the point has no marine coverage (inland). */
export async function fetchMarine(lat: number, lon: number): Promise<MarineData> {
  const params = new URLSearchParams({
    latitude: String(lat),
    longitude: String(lon),
    current:
      'wave_height,wave_direction,wave_period,swell_wave_height,swell_wave_period,swell_wave_direction,sea_surface_temperature',
    hourly: 'wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction',
    daily: 'wave_height_max,wave_period_max,wave_direction_dominant',
    timezone: 'auto',
    length_unit: 'imperial',
    forecast_days: '7',
  });
  const res = await fetch(`${MARINE_URL}?${params}`);
  if (!res.ok) throw new Error('No marine data');
  const d = await res.json();
  if (d.error || !d.current || d.current.wave_height == null) throw new Error('No marine data');

  // Water temp comes back in °C from the marine API; convert to °F.
  const cToF = (v: number | null | undefined) => (v == null ? null : v * 1.8 + 32);

  const nowMs = Date.now();
  const H = d.hourly;
  const hourly: SurfHour[] = [];
  for (let i = 0; i < H.time.length; i++) {
    const t = new Date(H.time[i]).getTime();
    if (t < nowMs - 3_600_000) continue;
    hourly.push({
      time: t,
      waveHeight: H.wave_height[i],
      wavePeriod: H.wave_period[i],
      swellHeight: H.swell_wave_height?.[i] ?? H.wave_height[i],
      swellPeriod: H.swell_wave_period?.[i] ?? H.wave_period[i],
      swellDir: H.swell_wave_direction?.[i] ?? H.wave_direction[i],
      windSpeed: 0,
      windDir: 0,
    });
    if (hourly.length >= 24) break;
  }

  const D = d.daily;
  const daily: SurfDay[] = D.time.map((t: string, i: number) => ({
    time: new Date(t).getTime(),
    waveMax: D.wave_height_max[i],
    periodMax: D.wave_period_max[i],
    dirDominant: D.wave_direction_dominant[i],
  }));

  return {
    current: {
      waveHeight: d.current.wave_height,
      wavePeriod: d.current.wave_period,
      waveDir: d.current.wave_direction,
      swellHeight: d.current.swell_wave_height,
      swellPeriod: d.current.swell_wave_period,
      swellDir: d.current.swell_wave_direction,
      waterTemp: cToF(d.current.sea_surface_temperature),
    },
    hourly,
    daily,
  };
}

/**
 * Reverse-geocode a friendly place name (city/town). Photon (OSM) is tried
 * first because it returns the actual town — BigDataCloud's `city` field snaps
 * to a broader administrative city (e.g. it reports "Albany" for Corvallis),
 * so it's used only as a fallback and we prefer its granular `locality`.
 */
export async function reverseName(lat: number, lon: number): Promise<string> {
  const PLACE_TYPES = new Set([
    'city',
    'town',
    'village',
    'hamlet',
    'municipality',
    'locality',
    'suburb',
    'neighbourhood',
  ]);
  try {
    const res = await fetch(`https://photon.komoot.io/reverse?lon=${lon}&lat=${lat}`);
    if (res.ok) {
      const d = await res.json();
      const p = d?.features?.[0]?.properties as
        | { name?: string; city?: string; county?: string; state?: string; type?: string }
        | undefined;
      if (p) {
        const name =
          p.city ||
          (p.type && PLACE_TYPES.has(p.type) ? p.name : undefined) ||
          p.name ||
          p.county ||
          p.state;
        if (name) return name;
      }
    }
  } catch {
    /* fall through to BigDataCloud */
  }
  try {
    const res = await fetch(
      `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${lat}&longitude=${lon}&localityLanguage=en`,
    );
    if (!res.ok) throw new Error('rev');
    const d = await res.json();
    return d.locality || d.city || d.principalSubdivision || d.countryName || 'Current Location';
  } catch {
    return 'Current Location';
  }
}

// ---------- WMO weather code → label + icon ----------

export type IconKey =
  | 'clear-day'
  | 'clear-night'
  | 'partly-day'
  | 'partly-night'
  | 'cloudy'
  | 'fog'
  | 'drizzle'
  | 'rain'
  | 'sleet'
  | 'snow'
  | 'thunder';

export function wmo(code: number, isDay = true): { label: string; icon: IconKey } {
  const day = <T,>(d: T, n: T) => (isDay ? d : n);
  switch (code) {
    case 0:
      return { label: 'Clear', icon: day<IconKey>('clear-day', 'clear-night') };
    case 1:
      return { label: 'Mostly Clear', icon: day<IconKey>('clear-day', 'clear-night') };
    case 2:
      return { label: 'Partly Cloudy', icon: day<IconKey>('partly-day', 'partly-night') };
    case 3:
      return { label: 'Cloudy', icon: 'cloudy' };
    case 45:
    case 48:
      return { label: 'Fog', icon: 'fog' };
    case 51:
    case 53:
    case 55:
      return { label: 'Drizzle', icon: 'drizzle' };
    case 56:
    case 57:
      return { label: 'Freezing Drizzle', icon: 'sleet' };
    case 61:
    case 63:
    case 65:
      return { label: 'Rain', icon: 'rain' };
    case 66:
    case 67:
      return { label: 'Freezing Rain', icon: 'sleet' };
    case 71:
    case 73:
    case 75:
    case 77:
      return { label: 'Snow', icon: 'snow' };
    case 80:
    case 81:
    case 82:
      return { label: 'Showers', icon: 'rain' };
    case 85:
    case 86:
      return { label: 'Snow Showers', icon: 'snow' };
    case 95:
    case 96:
    case 99:
      return { label: 'Thunderstorm', icon: 'thunder' };
    default:
      return { label: 'Cloudy', icon: 'cloudy' };
  }
}

const COMPASS = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];

export function compass(deg: number): string {
  return COMPASS[Math.round(((deg % 360) / 22.5)) % 16];
}

/** Surf quality rating from swell height, period, and wind. */
export function surfRating(
  swellFt: number,
  periodS: number,
  windMph: number,
  windRel: 'offshore' | 'onshore' | 'cross',
): { label: string; score: number; color: string } {
  let score = 0;
  score += Math.min(swellFt / 2, 3); // size (up to 3)
  score += Math.min(Math.max(periodS - 6, 0) / 3, 3); // period (up to 3)
  score += windRel === 'offshore' ? 2 : windRel === 'cross' ? 1 : 0;
  score -= Math.min(windMph / 12, 2); // wind chop penalty
  score = Math.max(0, Math.min(10, score));
  const label = score >= 7.5 ? 'Epic' : score >= 5.5 ? 'Good' : score >= 3.5 ? 'Fair' : 'Poor';
  const color = score >= 7.5 ? '#30D158' : score >= 5.5 ? '#34C759' : score >= 3.5 ? '#FFD60A' : '#FF9F0A';
  return { label, score, color };
}

/** Wind direction relative to the swell (a rough offshore/onshore heuristic). */
export function windRelation(windFromDeg: number, swellFromDeg: number): 'offshore' | 'onshore' | 'cross' {
  let delta = Math.abs(((windFromDeg - swellFromDeg + 540) % 360) - 180);
  if (delta > 135) return 'offshore';
  if (delta < 45) return 'onshore';
  return 'cross';
}
