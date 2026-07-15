import './style.css';
import { Globe, type PlacePin } from './globe';
import { PLACES } from './places';
import { buildShell, buildOnboarding, el, type Shell } from './ui';
import { Navigator, toast } from './navigation';
import { Field } from './field';
import { searchPlaces, type PlaceResult } from './geocode';
import { searchNearby, fetchPlaceDetails } from './nearby';
import { formatDistance, haversine } from './routing';
import { parseOpeningHours } from './hours';
import { categoryById } from './categories';
import { WeatherPage } from './weatherpage';
import { fetchCurrentBrief, wmo } from './weather';
import { weatherIcon } from './weathericons';
import { hasToken, setStoredToken, clearStoredToken, getActiveToken } from './config';

const mount = document.getElementById('app');
if (!mount) throw new Error('Missing #app mount point');

// Declared before boot() runs (boot is invoked during module init and assigns it).
let weather: WeatherPage | null = null;

if (hasToken()) {
  boot(mount);
} else {
  showOnboarding(mount);
}

function showOnboarding(root: HTMLElement, message?: string): void {
  root.replaceChildren();
  const ob = buildOnboarding(root, '');
  if (message) {
    ob.error.textContent = message;
    ob.error.classList.add('is-visible');
  }

  const attempt = () => {
    const value = ob.input.value.trim();
    if (!value) {
      ob.error.textContent = 'Please paste a token to continue.';
      ob.error.classList.add('is-visible');
      ob.input.focus();
      return;
    }
    setStoredToken(value);
    ob.overlay.classList.add('is-leaving');
    window.setTimeout(() => boot(root), 480);
  };

  ob.submit.addEventListener('click', attempt);
  ob.input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') attempt();
  });
  requestAnimationFrame(() => ob.input.focus());
}

async function boot(root: HTMLElement): Promise<void> {
  root.replaceChildren();
  const shell = buildShell(root);

  let globe: Globe;
  try {
    globe = new Globe(shell.cesiumContainer, shell.creditContainer);
  } catch (err) {
    handleTokenFailure(root, err);
    return;
  }

  globe.flyWholePlanet(0);
  if (import.meta.env.DEV) (window as unknown as { __globe: Globe }).__globe = globe;
  let field: Field;
  const nav = new Navigator(
    shell,
    globe,
    () => field?.lastLonLat() ?? null,
    () => field?.startTracking(),
  );
  if (import.meta.env.DEV) (window as unknown as { __nav: Navigator }).__nav = nav;
  field = new Field(shell, globe, nav);
  field.onLocation((fix) => nav.onLocation(fix));
  weather = new WeatherPage(shell.weatherPage);
  wireControls(shell, globe, nav, field);
  wireWeather(shell, globe, field);

  // Request the GPS fix immediately, in parallel with tile streaming, so the
  // camera can fly to (and follow) the user the moment both are ready — the
  // boot never stalls waiting on the location prompt.
  const locating = field.locateOnBoot();
  // Paint the weather chip as soon as we have a location, independent of tiles.
  void locating.then((ok) => {
    const at = ok ? field.lastLonLat() : null;
    if (at) void updateWeatherChip(shell, at[1], at[0]);
  });

  try {
    setLoading(shell, true, 'Loading photoreal tiles');
    await globe.initPhotoreal();
    setLoading(shell, false);
    const located = await locating;
    if (!located) globe.flyToPlace(PLACES[0], 4.2);
  } catch (err) {
    handleTokenFailure(root, err);
  }
}

function wireControls(shell: Shell, globe: Globe, nav: Navigator, field: Field): void {
  const closeMenu = () => shell.menu.classList.remove('is-open');

  // Tools dropdown
  shell.menuButton.addEventListener('click', (e) => {
    e.stopPropagation();
    shell.menu.classList.toggle('is-open');
  });
  shell.menu.addEventListener('click', (e) => e.stopPropagation());
  document.addEventListener('click', closeMenu);

  shell.menuLocate.addEventListener('click', () => {
    field.recenter();
    collapseSearch(shell);
    closeMenu();
  });
  shell.menuWaypoint.addEventListener('click', () => {
    field.addWaypointHere();
    closeMenu();
  });
  shell.menuWaypoints.addEventListener('click', () => {
    field.toggleWaypoints();
    closeMenu();
  });
  shell.menuRecord.addEventListener('click', () => {
    field.toggleRecording();
    closeMenu();
  });
  shell.menuHome.addEventListener('click', () => {
    if (nav.isActive) nav.end();
    globe.clearPlaces();
    hidePlaceCard(shell);
    globe.flyWholePlanet(2.6);
    collapseSearch(shell);
    closeMenu();
  });

  // Selecting a pin on the globe opens its card.
  globe.onPlaceTap((place) => {
    globe.focusPlace(place);
    showPlaceCard(shell, nav, field, place);
  });

  wireSearch(shell, globe, nav, field);
  wireCategories(shell, globe, nav, field);
  wireMapControls(shell, globe);
}

let chipToken = 0;
let lastChipAt = 0;

function wireWeather(shell: Shell, globe: Globe, field: Field): void {
  shell.weatherChip.addEventListener('click', () => {
    const at = field.lastLonLat() ?? globe.cameraCenterLonLat();
    if (!at) {
      toast(shell, 'Finding your location for weather…');
      return;
    }
    void weather?.open(at[1], at[0]);
  });

  // Refresh the at-a-glance chip from live location (throttled — weather is slow-moving).
  field.onLocation((fix) => {
    if (Date.now() - lastChipAt < 15 * 60 * 1000) return;
    void updateWeatherChip(shell, fix.lonlat[1], fix.lonlat[0]);
  });
}

async function updateWeatherChip(shell: Shell, lat: number, lon: number): Promise<void> {
  const current = ++chipToken;
  lastChipAt = Date.now();
  try {
    const brief = await fetchCurrentBrief(lat, lon);
    if (current !== chipToken) return;
    const icon = shell.weatherChip.querySelector('.weather-chip-icon');
    const temp = shell.weatherChip.querySelector('.weather-chip-temp');
    if (icon) icon.innerHTML = weatherIcon(wmo(brief.code, brief.isDay).icon);
    if (temp) temp.textContent = `${Math.round(brief.temp)}°`;
  } catch {
    lastChipAt = 0; // allow a retry on the next fix
  }
}

function wireMapControls(shell: Shell, globe: Globe): void {
  shell.ctrlCompass.addEventListener('click', () => globe.resetNorth());

  // Keep the compass needle pointing to true north as the camera turns.
  const needle = shell.ctrlCompass.querySelector('svg') as SVGElement | null;
  const spin = () => {
    if (needle) needle.style.transform = `rotate(${-globe.headingDeg()}deg)`;
  };
  globe.onCameraChange(spin);
  spin();
}

const dirIcon =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 2 22 12 12 22 2 12Z"/><path d="M9 13v-2a2 2 0 0 1 2-2h4"/><path d="M13 6l3 3-3 3"/></svg>';

/** Renders a list of places into the search dropdown, shared by search + categories. */
function renderResults(
  shell: Shell,
  results: PlaceResult[],
  onSelect: (r: PlaceResult) => void,
  onDirections: (r: PlaceResult) => void,
): void {
  shell.searchResults.replaceChildren();
  if (results.length === 0) {
    shell.searchResults.replaceChildren(
      el('div', { class: 'search-loading', textContent: 'No matches' }),
    );
    shell.searchResults.classList.add('is-open');
    return;
  }
  for (const r of results) {
    const lines: (Node | string)[] = [
      el('span', { class: 'search-result-name', textContent: r.name }),
    ];
    if (r.detail) {
      lines.push(el('span', { class: 'search-result-detail', textContent: r.detail }));
    }
    const label = el('button', { class: 'search-result-main', type: 'button' }, lines);
    label.addEventListener('click', () => {
      onSelect(r);
      collapseSearch(shell);
      shell.searchInput.blur();
    });
    const dir = el('button', {
      class: 'search-result-dir',
      type: 'button',
      title: 'Directions',
      innerHTML: dirIcon,
    });
    dir.addEventListener('click', () => {
      onDirections(r);
      collapseSearch(shell);
      shell.searchInput.blur();
    });
    shell.searchResults.append(el('div', { class: 'search-result' }, [label, dir]));
  }
  shell.searchResults.classList.add('is-open');
}

function selectFromSearch(shell: Shell, globe: Globe, nav: Navigator, field: Field, r: PlaceResult): void {
  rememberRecent(r);
  globe.showPlaces([r]);
  globe.focusPlace(r);
  showPlaceCard(shell, nav, field, r);
}

function startDirections(shell: Shell, nav: Navigator, r: PlaceResult): void {
  rememberRecent(r);
  hidePlaceCard(shell);
  void nav.directionsTo([r.lon, r.lat], r.name);
}

function wireSearch(shell: Shell, globe: Globe, nav: Navigator, field: Field): void {
  let token = 0;
  let debounce: number | undefined;
  let lastResults: PlaceResult[] = [];

  const renderLoading = () => {
    shell.searchResults.replaceChildren(
      el('div', { class: 'search-loading', textContent: 'Searching…' }),
    );
    shell.searchResults.classList.add('is-open');
  };

  const run = async (query: string) => {
    const current = ++token;
    if (query.trim().length < 2) {
      lastResults = [];
      collapseSearch(shell);
      return;
    }
    try {
      const results = await searchPlaces(query, field.lastLonLat());
      if (current !== token) return;
      lastResults = results;
      renderResults(
        shell,
        results,
        (r) => selectFromSearch(shell, globe, nav, field, r),
        (r) => startDirections(shell, nav, r),
      );
    } catch {
      if (current === token) {
        lastResults = [];
        renderResults(shell, [], () => {}, () => {});
      }
    }
  };

  shell.searchInput.addEventListener('input', () => {
    window.clearTimeout(debounce);
    const value = shell.searchInput.value;
    if (value.trim().length < 2) {
      lastResults = [];
      showHomeList(shell, globe, nav, field);
      return;
    }
    for (const c of shell.categories.querySelectorAll('.chip')) c.classList.remove('is-active');
    renderLoading(); // instant feedback while the query is in flight
    debounce = window.setTimeout(() => void run(value), 180);
  });
  shell.searchInput.addEventListener('focus', () => {
    if (shell.searchInput.value.trim().length < 2) showHomeList(shell, globe, nav, field);
  });
  shell.searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      if (lastResults.length) {
        selectFromSearch(shell, globe, nav, field, lastResults[0]);
        collapseSearch(shell);
        shell.searchInput.blur();
      }
    } else if (e.key === 'Escape') {
      shell.searchInput.value = '';
      collapseSearch(shell);
      shell.searchInput.blur();
    }
  });

  document.addEventListener('click', (e) => {
    const t = e.target as HTMLElement;
    if (!t.closest('.search-bar') && !t.closest('.categories')) collapseSearch(shell);
  });
}

/** Recents + favorites shown when the search field is focused but empty. */
function showHomeList(shell: Shell, globe: Globe, nav: Navigator, field: Field): void {
  const recents = loadRecents();
  const favorites = field.listWaypoints();
  if (recents.length === 0 && favorites.length === 0) {
    collapseSearch(shell);
    return;
  }

  shell.searchResults.replaceChildren();

  const section = (title: string) =>
    shell.searchResults.append(el('div', { class: 'search-section', textContent: title }));

  const row = (name: string, detail: string, icon: string, onGo: () => void) => {
    const textCol = el('span', { class: 'search-result-textcol' }, [
      el('span', { class: 'search-result-name', textContent: name }),
      detail ? el('span', { class: 'search-result-detail', textContent: detail }) : el('span'),
    ]);
    const label = el('button', { class: 'search-result-main has-lead', type: 'button' }, [
      el('span', { class: 'search-result-lead', innerHTML: icon }),
      textCol,
    ]);
    label.addEventListener('click', () => {
      onGo();
      collapseSearch(shell);
      shell.searchInput.blur();
    });
    shell.searchResults.append(el('div', { class: 'search-result' }, [label]));
  };

  if (recents.length) {
    section('Recents');
    for (const r of recents) {
      row(r.name, r.detail, homeIcons.clock, () => selectFromSearch(shell, globe, nav, field, r));
    }
  }
  if (favorites.length) {
    section('Favorites');
    for (const f of favorites) {
      row(f.label, 'Saved place', homeIcons.star, () => {
        globe.flyToLonLat(f.lon, f.lat, 500, 0, -45, 2.6);
      });
    }
  }
  shell.searchResults.classList.add('is-open');
}

const homeIcons = {
  clock:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  star:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 17l-5.2 2.7 1-5.9-4.3-4.1 5.9-.8Z"/></svg>',
};

// ---------- Recents (localStorage) ----------

const RECENTS_KEY = 'phantom-eye.recents';

function loadRecents(): PlaceResult[] {
  try {
    const raw = localStorage.getItem(RECENTS_KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed.slice(0, 8) : [];
  } catch {
    return [];
  }
}

function rememberRecent(r: PlaceResult): void {
  try {
    const list = loadRecents().filter((p) => !(p.lon === r.lon && p.lat === r.lat));
    list.unshift(r);
    localStorage.setItem(RECENTS_KEY, JSON.stringify(list.slice(0, 8)));
  } catch {
    /* ignore private-mode storage failures */
  }
}

function wireCategories(shell: Shell, globe: Globe, nav: Navigator, field: Field): void {
  let busy = false;
  shell.categories.addEventListener('click', async (e) => {
    const chip = (e.target as HTMLElement).closest('.chip') as HTMLElement | null;
    if (!chip || busy) return;
    const cat = categoryById(chip.dataset.cat);
    if (!cat) return;

    const near = field.lastLonLat() ?? globe.cameraCenterLonLat();
    if (!near) {
      toast(shell, 'Move to a place first, then pick a category.');
      return;
    }

    for (const c of shell.categories.querySelectorAll('.chip')) c.classList.remove('is-active');
    chip.classList.add('is-active', 'is-loading');
    busy = true;
    try {
      const results = await searchNearby(cat, near);
      if (results.length === 0) {
        toast(shell, `No ${cat.label.toLowerCase()} found nearby.`);
        return;
      }
      globe.showPlaces(results);
      globe.framePlaces();
      renderResults(
        shell,
        results,
        (r) => {
          globe.focusPlace(r);
          showPlaceCard(shell, nav, field, r);
        },
        (r) => startDirections(shell, nav, r),
      );
    } catch {
      toast(shell, 'Couldn’t load nearby places. Try again.');
    } finally {
      chip.classList.remove('is-loading');
      busy = false;
    }
  });
}

// ---------- Place card (Apple-style) ----------

let cardToken = 0;

function showPlaceCard(shell: Shell, nav: Navigator, field: Field, place: PlacePin): void {
  const token = ++cardToken;
  const cat = categoryById(place.categoryId);
  const parts = [place.detail || cat?.label || 'Dropped pin'];
  const origin = field.lastLonLat();
  if (origin) parts.push(formatDistance(haversine(origin, [place.lon, place.lat])));
  const subtitle = parts.filter(Boolean).join('  ·  ');

  const close = el('button', { class: 'place-card-close', type: 'button', innerHTML: '&times;' });
  close.addEventListener('click', () => hidePlaceCard(shell));

  const info = el('div', { class: 'place-card-info' });

  const directions = el('button', { class: 'place-card-dir', type: 'button' }, [
    el('span', { class: 'place-card-dir-icon', innerHTML: dirIcon }),
    el('span', { textContent: 'Directions' }),
  ]);
  directions.addEventListener('click', () => {
    hidePlaceCard(shell);
    void nav.directionsTo([place.lon, place.lat], place.name);
  });

  // Secondary actions: Favorite + Share, Apple-style circular buttons.
  const favorite = actionButton(cardIcons.star, 'Favorite', () => {
    field.addNamedWaypoint(place.lon, place.lat, place.name);
    favorite.classList.add('is-done');
  });
  const share = actionButton(cardIcons.share, 'Share', () => sharePlace(shell, place));
  const acts = [directions, favorite, share];
  if (place.categoryId === 'surf') {
    acts.push(
      actionButton(cardIcons.surf, 'Surf', () => {
        hidePlaceCard(shell);
        void weather?.open(place.lat, place.lon, place.name, 'surf');
      }),
    );
  }
  const actions = el('div', { class: 'place-card-actions' }, acts);

  const card = el('div', { class: 'place-card glass' }, [
    el('div', { class: 'place-card-head' }, [
      el('div', { class: 'place-card-text' }, [
        el('div', { class: 'place-card-name', textContent: place.name }),
        el('div', { class: 'place-card-detail', textContent: subtitle }),
      ]),
      close,
    ]),
    info,
    actions,
  ]);
  shell.placeCard.replaceChildren(card);
  shell.placeCard.classList.add('is-visible');

  renderCardInfo(info, place);
  void enrichPlaceCard(info, place, token);
}

function actionButton(icon: string, label: string, onClick: () => void): HTMLButtonElement {
  const btn = el('button', { class: 'place-card-act', type: 'button', title: label }, [
    el('span', { class: 'place-card-act-icon', innerHTML: icon }),
    el('span', { class: 'place-card-act-label', textContent: label }),
  ]) as HTMLButtonElement;
  btn.addEventListener('click', onClick);
  return btn;
}

async function sharePlace(shell: Shell, place: PlacePin): Promise<void> {
  const url = `https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lon}`;
  const data = { title: place.name, text: place.name, url };
  try {
    if (navigator.share) {
      await navigator.share(data);
      return;
    }
    await navigator.clipboard.writeText(url);
    toast(shell, 'Link copied to clipboard');
  } catch {
    /* user dismissed the share sheet */
  }
}

const cardIcons = {
  star:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 17l-5.2 2.7 1-5.9-4.3-4.1 5.9-.8Z"/></svg>',
  share:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 15V4"/><path d="M8 8l4-4 4 4"/><path d="M6 12v6a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-6"/></svg>',
  surf:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 16c4 0 4-2 8-2s4 2 8 2"/><path d="M3 20c4 0 4-2 8-2s4 2 8 2"/><path d="M14 4c3 3 3 7 0 10"/></svg>',
};

/** Fill the info section (hours, phone, website, address) from what we have. */
function renderCardInfo(info: HTMLElement, place: PlacePin): void {
  const rows: HTMLElement[] = [];

  if (place.openingHours) {
    const { openNow, today } = parseOpeningHours(place.openingHours);
    const value = el('span', { class: 'place-info-text' });
    if (openNow !== null) {
      value.append(
        el('span', {
          class: `place-info-state ${openNow ? 'is-open' : 'is-closed'}`,
          textContent: openNow ? 'Open' : 'Closed',
        }),
      );
      if (today) value.append(el('span', { textContent: ` · ${today}` }));
    } else {
      value.textContent = place.openingHours;
    }
    rows.push(infoRow(infoIcons.clock, value));
  }

  if (place.phone) {
    const link = el('a', {
      class: 'place-info-text place-info-link',
      href: `tel:${place.phone.replace(/[^+\d]/g, '')}`,
      textContent: place.phone,
    });
    rows.push(infoRow(infoIcons.phone, link));
  }

  if (place.website) {
    const link = el('a', {
      class: 'place-info-text place-info-link',
      href: place.website,
      target: '_blank',
      rel: 'noreferrer noopener',
      textContent: hostname(place.website),
    });
    rows.push(infoRow(infoIcons.web, link));
  }

  if (place.address && place.address !== place.detail) {
    rows.push(infoRow(infoIcons.pin, el('span', { class: 'place-info-text', textContent: place.address })));
  }

  info.replaceChildren(...rows);
}

async function enrichPlaceCard(info: HTMLElement, place: PlacePin, token: number): Promise<void> {
  const needsInfo = !place.openingHours && !place.phone && !place.website;
  if (!needsInfo || !place.osmType || !place.osmId) return;
  try {
    const details = await fetchPlaceDetails(place.osmType, place.osmId);
    if (token !== cardToken) return; // card was replaced
    Object.assign(place, {
      openingHours: place.openingHours ?? details.openingHours,
      phone: place.phone ?? details.phone,
      website: place.website ?? details.website,
      address: place.address ?? details.address,
    });
    renderCardInfo(info, place);
  } catch {
    /* keep the basic card */
  }
}

function infoRow(icon: string, value: Node): HTMLElement {
  return el('div', { class: 'place-info-row' }, [
    el('span', { class: 'place-info-icon', innerHTML: icon }),
    value,
  ]);
}

function hostname(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
}

const infoIcons = {
  clock:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  phone:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M6 3h3l2 5-2 1a12 12 0 0 0 5 5l1-2 5 2v3a2 2 0 0 1-2 2A16 16 0 0 1 4 5a2 2 0 0 1 2-2Z"/></svg>',
  web:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><line x1="3" y1="12" x2="21" y2="12"/></svg>',
  pin:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 21s-6-5.7-6-10a6 6 0 0 1 12 0c0 4.3-6 10-6 10Z"/><circle cx="12" cy="11" r="2.2"/></svg>',
};

function hidePlaceCard(shell: Shell): void {
  shell.placeCard.classList.remove('is-visible');
}

function collapseSearch(shell: Shell): void {
  shell.searchResults.classList.remove('is-open');
}

function setLoading(shell: Shell, on: boolean, label?: string): void {
  if (label) shell.loadingLabel.textContent = label;
  shell.loading.classList.toggle('is-visible', on);
}

function handleTokenFailure(root: HTMLElement, err: unknown): void {
  console.error('Cesium initialization failed:', err);
  const active = getActiveToken();
  clearStoredToken();
  const hint = active
    ? 'That token was rejected. Double-check it and try again.'
    : 'A Cesium ion token is required.';
  showOnboarding(root, hint);
}
