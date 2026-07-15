import { el } from './ui';
import { weatherIcon } from './weathericons';
import { haversine } from './routing';
import {
  fetchWeather,
  fetchMarine,
  wmo,
  compass,
  surfRating,
  windRelation,
  type WeatherData,
  type MarineData,
} from './weather';

/** A browsable surf spot near the viewed location. */
export interface SurfSpot {
  name: string;
  lat: number;
  lon: number;
}

/** Full-screen Apple-Weather-style page with a Surfline-style surf report. */
export class WeatherPage {
  private token = 0;
  private viewing: { lat: number; lon: number } | null = null;

  constructor(
    private readonly root: HTMLElement,
    private readonly findSurfSpots?: (lat: number, lon: number) => Promise<SurfSpot[]>,
  ) {}

  get isOpen(): boolean {
    return this.root.classList.contains('is-open');
  }

  close(): void {
    this.root.classList.remove('is-open');
  }

  async open(lat: number, lon: number, name?: string, focus?: 'surf'): Promise<void> {
    const current = ++this.token;
    this.viewing = { lat, lon };
    this.root.classList.add('is-open');
    this.root.querySelector('.wx-scroll')?.scrollTo({ top: 0 });
    this.renderSkeleton(name);

    let weather: WeatherData;
    try {
      weather = await fetchWeather(lat, lon);
    } catch {
      if (current === this.token) this.renderError();
      return;
    }
    if (current !== this.token) return;
    this.render(weather);

    // Surf loads in parallel and slots in when ready (coastal points only).
    void fetchMarine(lat, lon)
      .then((marine) => {
        if (current !== this.token) return;
        this.renderSurf(weather, marine, focus);
      })
      .catch(() => {
        if (current === this.token) this.renderSurf(weather, null, focus);
      });

    // Nearby surf spots browse list — loads independently of marine data so it
    // works even from an inland location.
    void this.loadSpots(lat, lon, current);
  }

  /** Fetches and renders the browsable "Surf Spots Nearby" list. */
  private async loadSpots(lat: number, lon: number, current: number): Promise<void> {
    if (!this.findSurfSpots) return;
    const host = this.root.querySelector('.wx-spots');
    if (!host) return;
    host.replaceChildren(
      el('div', { class: 'wx-card' }, [
        cardTitle('Surf Spots Nearby'),
        el('div', { class: 'wx-surf-loading', textContent: 'Finding surf spots…' }),
      ]),
    );

    let spots: SurfSpot[];
    try {
      spots = await this.findSurfSpots(lat, lon);
    } catch {
      spots = [];
    }
    if (current !== this.token) return;
    if (!host.isConnected) {
      const fresh = this.root.querySelector('.wx-spots');
      if (!fresh) return;
      return this.paintSpots(fresh, spots);
    }
    this.paintSpots(host, spots);
  }

  private paintSpots(host: Element, spots: SurfSpot[]): void {
    if (!spots.length) {
      host.replaceChildren(
        el('div', { class: 'wx-card' }, [
          cardTitle('Surf Spots Nearby'),
          el('div', { class: 'wx-surf-empty', textContent: 'No surf spots found around here.' }),
        ]),
      );
      return;
    }

    const here = this.viewing;
    const list = el('div', { class: 'wx-spots-list' });
    for (const s of spots) {
      const active = !!here && Math.abs(here.lat - s.lat) < 1e-5 && Math.abs(here.lon - s.lon) < 1e-5;
      const dist = here ? haversine([here.lon, here.lat], [s.lon, s.lat]) : 0;
      const row = el('button', { class: `wx-spot${active ? ' is-active' : ''}`, type: 'button' }, [
        el('span', { class: 'wx-spot-name', textContent: s.name }),
        el('span', { class: 'wx-spot-dist', textContent: here ? fmtMiles(dist) : '' }),
      ]);
      row.addEventListener('click', () => {
        if (active) return;
        void this.open(s.lat, s.lon, s.name, 'surf');
      });
      list.append(row);
    }
    host.replaceChildren(el('div', { class: 'wx-card wx-spots-card' }, [cardTitle('Surf Spots Nearby'), list]));
  }

  // ---------- Rendering ----------

  private renderSkeleton(name?: string): void {
    const close = el('button', { class: 'wx-close', type: 'button', innerHTML: '&times;' });
    close.addEventListener('click', () => this.close());
    this.root.replaceChildren(
      el('div', { class: 'wx-scroll' }, [
        el('div', { class: 'wx-top' }, [
          close,
          el('div', { class: 'wx-place', textContent: name ?? 'Loading…' }),
        ]),
        el('div', { class: 'wx-loading' }, [el('div', { class: 'loading-ring' })]),
      ]),
    );
  }

  private renderError(): void {
    const close = el('button', { class: 'wx-close', type: 'button', innerHTML: '&times;' });
    close.addEventListener('click', () => this.close());
    this.root.replaceChildren(
      el('div', { class: 'wx-scroll' }, [
        el('div', { class: 'wx-top' }, [close, el('div', { class: 'wx-place', textContent: 'Weather' })]),
        el('div', { class: 'wx-loading', textContent: 'Weather is unavailable right now.' }),
      ]),
    );
  }

  private render(w: WeatherData): void {
    const c = w.current;
    const cond = wmo(c.code, c.isDay);
    this.root.dataset.sky = c.isDay ? skyClass(c.code) : 'night';

    const close = el('button', { class: 'wx-close', type: 'button', innerHTML: '&times;' });
    close.addEventListener('click', () => this.close());

    const scroll = el('div', { class: 'wx-scroll' }, [
      el('div', { class: 'wx-top' }, [
        close,
        el('div', { class: 'wx-place', textContent: w.name }),
      ]),
      // Hero
      el('div', { class: 'wx-hero' }, [
        el('div', { class: 'wx-temp', textContent: `${Math.round(c.temp)}°` }),
        el('div', { class: 'wx-cond', textContent: cond.label }),
        el('div', {
          class: 'wx-hilo',
          textContent: `H:${Math.round(w.daily[0].max)}°  L:${Math.round(w.daily[0].min)}°  ·  Feels ${Math.round(c.feelsLike)}°`,
        }),
      ]),
      this.hourlyCard(w),
      this.dailyCard(w),
      this.detailsGrid(w),
      el('div', { class: 'wx-surf' }, [el('div', { class: 'wx-surf-loading', textContent: 'Loading surf report…' })]),
      el('div', { class: 'wx-spots' }),
    ]);

    this.root.replaceChildren(scroll);
  }

  private hourlyCard(w: WeatherData): HTMLElement {
    const strip = el('div', { class: 'wx-hourly' });
    w.hourly.forEach((h, i) => {
      const label = i === 0 ? 'Now' : new Date(h.time).toLocaleTimeString([], { hour: 'numeric' });
      strip.append(
        el('div', { class: 'wx-hour' }, [
          el('div', { class: 'wx-hour-t', textContent: label }),
          el('div', { class: 'wx-hour-i', innerHTML: weatherIcon(wmo(h.code, h.isDay).icon) }),
          h.precipProb >= 20
            ? el('div', { class: 'wx-hour-p', textContent: `${h.precipProb}%` })
            : el('div', { class: 'wx-hour-p' }),
          el('div', { class: 'wx-hour-d', textContent: `${Math.round(h.temp)}°` }),
        ]),
      );
    });
    return el('div', { class: 'wx-card' }, [cardTitle('Hourly Forecast'), strip]);
  }

  private dailyCard(w: WeatherData): HTMLElement {
    const list = el('div', { class: 'wx-daily' });
    const span = Math.max(1, w.weekMax - w.weekMin);
    w.daily.forEach((d, i) => {
      const day = i === 0 ? 'Today' : new Date(d.time).toLocaleDateString([], { weekday: 'short' });
      const left = ((d.min - w.weekMin) / span) * 100;
      const width = ((d.max - d.min) / span) * 100;
      const fill = el('div', { class: 'wx-range-fill' });
      fill.setAttribute(
        'style',
        `left:${left}%;width:${width}%;background:linear-gradient(90deg, ${tempColor(d.min)}, ${tempColor(d.max)})`,
      );
      const bar = el('div', { class: 'wx-range' }, [fill]);
      list.append(
        el('div', { class: 'wx-day' }, [
          el('div', { class: 'wx-day-name', textContent: day }),
          el('div', {
            class: 'wx-day-i',
            innerHTML: weatherIcon(wmo(d.code, true).icon) + (d.precipProb >= 20 ? `<span class="wx-day-p">${d.precipProb}%</span>` : ''),
          }),
          el('div', { class: 'wx-day-lo', textContent: `${Math.round(d.min)}°` }),
          bar,
          el('div', { class: 'wx-day-hi', textContent: `${Math.round(d.max)}°` }),
        ]),
      );
    });
    return el('div', { class: 'wx-card' }, [cardTitle('10-Day Forecast'), list]);
  }

  private detailsGrid(w: WeatherData): HTMLElement {
    const c = w.current;
    const d0 = w.daily[0];
    const tiles = [
      tile('UV Index', `${Math.round(c.uv)}`, uvLabel(c.uv)),
      tile('Sunrise', clock(d0.sunrise), `Sunset ${clock(d0.sunset)}`),
      tile('Wind', `${Math.round(c.windSpeed)} mph`, `${compass(c.windDir)} · gust ${Math.round(c.windGust)}`),
      tile('Humidity', `${Math.round(c.humidity)}%`, `Dew feels ${Math.round(c.feelsLike)}°`),
      tile('Visibility', `${(c.visibility / 1609).toFixed(1)} mi`, ''),
      tile('Pressure', `${(c.pressure * 0.02953).toFixed(2)} in`, ''),
      tile('Precipitation', `${c.precip.toFixed(2)} in`, `${d0.precipProb}% chance`),
      tile('Cloud Cover', `${Math.round(c.cloud)}%`, ''),
    ];
    return el('div', { class: 'wx-grid' }, tiles);
  }

  private renderSurf(w: WeatherData, m: MarineData | null, focus?: 'surf'): void {
    const host = this.root.querySelector('.wx-surf');
    if (!host) return;

    if (!m) {
      host.replaceChildren(
        el('div', { class: 'wx-card' }, [
          cardTitle('Surf Report'),
          el('div', { class: 'wx-surf-empty', textContent: 'No marine data here — open a coastal spot for the surf forecast.' }),
        ]),
      );
      return;
    }

    const c = m.current;
    const rel = windRelation(w.current.windDir, c.swellDir);
    const rating = surfRating(c.swellHeight, c.swellPeriod, w.current.windSpeed, rel);

    const stats = el('div', { class: 'wx-surf-stats' }, [
      surfStat(`${c.waveHeight.toFixed(1)}–${(c.waveHeight * 1.4).toFixed(1)} ft`, 'Wave height'),
      surfStat(`${Math.round(c.swellPeriod)} s`, 'Swell period'),
      surfStat(`${compass(c.swellDir)}`, 'Swell dir'),
      surfStat(`${Math.round(w.current.windSpeed)} mph ${rel}`, 'Wind'),
      surfStat(c.waterTemp != null ? `${Math.round(c.waterTemp)}°` : '—', 'Water temp'),
    ]);

    const hourly = el('div', { class: 'wx-surf-hours' });
    m.hourly.forEach((h, i) => {
      const label = i === 0 ? 'Now' : new Date(h.time).toLocaleTimeString([], { hour: 'numeric' });
      hourly.append(
        el('div', { class: 'wx-surf-hour' }, [
          el('div', { class: 'wx-hour-t', textContent: label }),
          el('div', { class: 'wx-surf-wave', textContent: `${h.waveHeight.toFixed(1)}` }),
          el('div', { class: 'wx-surf-unit', textContent: 'ft' }),
          el('div', { class: 'wx-hour-p', textContent: `${Math.round(h.swellPeriod)}s` }),
        ]),
      );
    });

    const days = el('div', { class: 'wx-surf-days' });
    m.daily.forEach((d, i) => {
      const day = i === 0 ? 'Today' : new Date(d.time).toLocaleDateString([], { weekday: 'short' });
      days.append(
        el('div', { class: 'wx-surf-day' }, [
          el('div', { class: 'wx-day-name', textContent: day }),
          el('div', { class: 'wx-surf-dwave', textContent: `${d.waveMax.toFixed(1)} ft` }),
          el('div', { class: 'wx-day-p', textContent: `${Math.round(d.periodMax)}s ${compass(d.dirDominant)}` }),
        ]),
      );
    });

    host.replaceChildren(
      el('div', { class: 'wx-card wx-surf-card' }, [
        el('div', { class: 'wx-surf-head' }, [
          cardTitle('Surf Report'),
          ratingBadge(rating.label, rating.color),
        ]),
        stats,
        el('div', { class: 'wx-sub', textContent: 'Next hours' }),
        hourly,
        el('div', { class: 'wx-sub', textContent: '7-day swell' }),
        days,
      ]),
    );

    if (focus === 'surf') host.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
}

// ---------- small builders ----------

function cardTitle(text: string): HTMLElement {
  return el('div', { class: 'wx-card-title', textContent: text });
}

function tile(label: string, value: string, sub: string): HTMLElement {
  return el('div', { class: 'wx-tile' }, [
    el('div', { class: 'wx-tile-label', textContent: label }),
    el('div', { class: 'wx-tile-value', textContent: value }),
    el('div', { class: 'wx-tile-sub', textContent: sub }),
  ]);
}

function ratingBadge(label: string, color: string): HTMLElement {
  const badge = el('div', { class: 'wx-rating' }, [
    el('span', { class: 'wx-rating-dot' }),
    el('span', { textContent: label }),
  ]);
  badge.setAttribute('style', `--rating:${color}`);
  return badge;
}

function surfStat(value: string, label: string): HTMLElement {
  return el('div', { class: 'wx-surf-stat' }, [
    el('div', { class: 'wx-surf-stat-v', textContent: value }),
    el('div', { class: 'wx-surf-stat-l', textContent: label }),
  ]);
}

function clock(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function fmtMiles(meters: number): string {
  const mi = meters / 1609.34;
  if (mi < 0.1) return 'here';
  if (mi < 10) return `${mi.toFixed(1)} mi`;
  return `${Math.round(mi)} mi`;
}

function uvLabel(uv: number): string {
  if (uv < 3) return 'Low';
  if (uv < 6) return 'Moderate';
  if (uv < 8) return 'High';
  if (uv < 11) return 'Very High';
  return 'Extreme';
}

function tempColor(f: number): string {
  if (f <= 32) return '#5AC8FA';
  if (f <= 50) return '#64D2FF';
  if (f <= 65) return '#30D158';
  if (f <= 78) return '#FFD60A';
  if (f <= 90) return '#FF9F0A';
  return '#FF453A';
}

function skyClass(code: number): string {
  if (code === 0 || code === 1) return 'clear';
  if (code === 2) return 'partly';
  if (code >= 51 && code <= 67) return 'rain';
  if (code >= 80 && code <= 82) return 'rain';
  if (code >= 71 && code <= 86) return 'snow';
  if (code >= 95) return 'storm';
  return 'cloudy';
}
