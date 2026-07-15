import './style.css';
import { Globe, type PlacePin } from './globe';
import { PLACES } from './places';
import { buildShell, buildOnboarding, el, type Shell } from './ui';
import { Navigator, toast } from './navigation';
import { Field } from './field';
import { searchPlaces, type PlaceResult } from './geocode';
import { searchNearby } from './nearby';
import { categoryById } from './categories';
import { hasToken, setStoredToken, clearStoredToken, getActiveToken } from './config';

const mount = document.getElementById('app');
if (!mount) throw new Error('Missing #app mount point');

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
  const nav = new Navigator(shell, globe, () => field?.lastLonLat() ?? null);
  field = new Field(shell, globe, nav);
  wireControls(shell, globe, nav, field);

  // Request the GPS fix immediately, in parallel with tile streaming, so the
  // camera can fly to (and follow) the user the moment both are ready — the
  // boot never stalls waiting on the location prompt.
  const locating = field.locateOnBoot();

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
    showPlaceCard(shell, nav, place);
  });

  wireSearch(shell, globe, nav, field);
  wireCategories(shell, globe, nav, field);
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

function selectFromSearch(shell: Shell, globe: Globe, nav: Navigator, r: PlaceResult): void {
  globe.showPlaces([r]);
  globe.focusPlace(r);
  showPlaceCard(shell, nav, r);
}

function startDirections(shell: Shell, nav: Navigator, r: PlaceResult): void {
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
        (r) => selectFromSearch(shell, globe, nav, r),
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
      collapseSearch(shell);
      return;
    }
    for (const c of shell.categories.querySelectorAll('.chip')) c.classList.remove('is-active');
    renderLoading(); // instant feedback while the query is in flight
    debounce = window.setTimeout(() => void run(value), 180);
  });
  shell.searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      if (lastResults.length) {
        selectFromSearch(shell, globe, nav, lastResults[0]);
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
          showPlaceCard(shell, nav, r);
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

function showPlaceCard(shell: Shell, nav: Navigator, place: PlacePin): void {
  const cat = categoryById(place.categoryId);
  const subtitle = place.detail || cat?.label || 'Dropped pin';

  const close = el('button', { class: 'place-card-close', type: 'button', innerHTML: '&times;' });
  close.addEventListener('click', () => hidePlaceCard(shell));

  const directions = el('button', { class: 'place-card-dir', type: 'button' }, [
    el('span', { class: 'place-card-dir-icon', innerHTML: dirIcon }),
    el('span', { textContent: 'Directions' }),
  ]);
  directions.addEventListener('click', () => {
    hidePlaceCard(shell);
    void nav.directionsTo([place.lon, place.lat], place.name);
  });

  const card = el('div', { class: 'place-card glass' }, [
    el('div', { class: 'place-card-head' }, [
      el('div', { class: 'place-card-text' }, [
        el('div', { class: 'place-card-name', textContent: place.name }),
        el('div', { class: 'place-card-detail', textContent: subtitle }),
      ]),
      close,
    ]),
    directions,
  ]);
  shell.placeCard.replaceChildren(card);
  shell.placeCard.classList.add('is-visible');
}

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
