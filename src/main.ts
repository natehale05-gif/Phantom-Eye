import './style.css';
import { Globe } from './globe';
import { PLACES } from './places';
import { buildShell, buildOnboarding, el, type Shell } from './ui';
import { Navigator } from './navigation';
import { Field } from './field';
import { searchPlaces } from './geocode';
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
    globe.flyWholePlanet(2.6);
    collapseSearch(shell);
    closeMenu();
  });

  wireSearch(shell, globe, nav, field);
}

const dirIcon =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 2 22 12 12 22 2 12Z"/><path d="M9 13v-2a2 2 0 0 1 2-2h4"/><path d="M13 6l3 3-3 3"/></svg>';

interface ResultItem {
  name: string;
  detail: string;
  fly: () => void;
  directions: () => void;
}

function wireSearch(shell: Shell, globe: Globe, nav: Navigator, field: Field): void {
  let token = 0;
  let debounce: number | undefined;
  let lastResults: ResultItem[] = [];

  const renderLoading = () => {
    shell.searchResults.replaceChildren(
      el('div', { class: 'search-loading', textContent: 'Searching…' }),
    );
    shell.searchResults.classList.add('is-open');
  };

  const render = (items: ResultItem[]) => {
    lastResults = items;
    shell.searchResults.replaceChildren();
    if (items.length === 0) {
      shell.searchResults.replaceChildren(
        el('div', { class: 'search-loading', textContent: 'No matches' }),
      );
      shell.searchResults.classList.add('is-open');
      return;
    }
    for (const item of items) {
      const lines: (Node | string)[] = [
        el('span', { class: 'search-result-name', textContent: item.name }),
      ];
      if (item.detail) {
        lines.push(el('span', { class: 'search-result-detail', textContent: item.detail }));
      }
      const label = el('button', { class: 'search-result-main', type: 'button' }, lines);
      label.addEventListener('click', () => {
        item.fly();
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
        item.directions();
        collapseSearch(shell);
        shell.searchInput.blur();
      });
      shell.searchResults.append(el('div', { class: 'search-result' }, [label, dir]));
    }
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
      render(
        results.map((r) => ({
          name: r.name,
          detail: r.detail,
          fly: () => globe.showPlace(r.lon, r.lat, r.name),
          directions: () => void nav.directionsTo([r.lon, r.lat], r.name),
        })),
      );
    } catch {
      if (current === token) render([]);
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
    renderLoading(); // instant feedback while the query is in flight
    debounce = window.setTimeout(() => void run(value), 180);
  });
  shell.searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      // Enter jumps straight to the top result.
      if (lastResults.length) {
        lastResults[0].fly();
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
    if (!(e.target as HTMLElement).closest('.search-bar')) collapseSearch(shell);
  });
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
