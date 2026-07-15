import './style.css';
import { Globe } from './globe';
import { PLACES } from './places';
import { buildShell, buildOnboarding, el, type Shell } from './ui';
import { Navigator } from './navigation';
import { Field } from './field';
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
  let field: Field;
  const nav = new Navigator(shell, globe, () => field?.lastLonLat() ?? null);
  field = new Field(shell, globe, nav);
  wireControls(shell, globe, nav, field);

  try {
    setLoading(shell, true, 'Loading photoreal tiles');
    await globe.initPhotoreal();
    setLoading(shell, false);
    globe.flyToPlace(PLACES[0], 4.2);
  } catch (err) {
    handleTokenFailure(root, err);
  }
}

function wireControls(shell: Shell, globe: Globe, nav: Navigator, field: Field): void {
  // Destinations
  shell.destinationsRail.addEventListener('click', (e) => {
    const card = (e.target as HTMLElement).closest<HTMLElement>('.destination-card');
    if (!card?.dataset.placeId) return;
    const place = PLACES.find((p) => p.id === card.dataset.placeId);
    if (!place) return;
    setActiveCard(shell, card);
    globe.flyToPlace(place);
    collapseSearch(shell);
  });

  // Home / whole-planet view
  shell.homeButton.addEventListener('click', () => {
    setActiveCard(shell, null);
    if (nav.isActive) nav.end();
    globe.flyWholePlanet(2.6);
    collapseSearch(shell);
  });

  // Field tools
  shell.locateButton.addEventListener('click', () => {
    field.recenter();
    collapseSearch(shell);
  });
  shell.waypointButton.addEventListener('click', () => field.addWaypointHere());
  shell.waypointsButton.addEventListener('click', () => field.toggleWaypoints());
  shell.recordButton.addEventListener('click', () => field.toggleRecording());

  wireSearch(shell, globe, nav);
}

function wireSearch(shell: Shell, globe: Globe, nav: Navigator): void {
  let token = 0;
  let debounce: number | undefined;

  const render = (
    items: { displayName: string; fly: () => void; directions: () => void }[],
  ) => {
    shell.searchResults.replaceChildren();
    if (items.length === 0) {
      shell.searchResults.classList.remove('is-open');
      return;
    }
    for (const item of items) {
      const label = el('button', {
        class: 'search-result-main',
        type: 'button',
        textContent: item.displayName,
      });
      label.addEventListener('click', () => {
        item.fly();
        collapseSearch(shell);
        shell.searchInput.blur();
      });
      const dir = el('button', {
        class: 'search-result-dir',
        type: 'button',
        title: 'Directions',
        innerHTML:
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 2 22 12 12 22 2 12Z"/><path d="M9 13v-2a2 2 0 0 1 2-2h4"/><path d="M13 6l3 3-3 3"/></svg>',
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
      render([]);
      return;
    }
    try {
      const results = await globe.search(query);
      if (current !== token) return;
      render(
        results.slice(0, 6).map((r) => {
          const lonlat = Globe.destinationLonLat(r.destination);
          return {
            displayName: r.displayName,
            fly: () => globe.flyToDestination(r.destination),
            directions: () => void nav.directionsTo(lonlat, r.displayName),
          };
        }),
      );
    } catch {
      if (current === token) render([]);
    }
  };

  shell.searchInput.addEventListener('input', () => {
    window.clearTimeout(debounce);
    const value = shell.searchInput.value;
    debounce = window.setTimeout(() => void run(value), 250);
  });
  shell.searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
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

function setActiveCard(shell: Shell, card: HTMLElement | null): void {
  shell.destinationsRail
    .querySelectorAll('.destination-card.is-active')
    .forEach((c) => c.classList.remove('is-active'));
  card?.classList.add('is-active');
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
