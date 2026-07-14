import './style.css';
import { Globe, type SceneMode } from './globe';
import { PLACES } from './places';
import { buildShell, buildOnboarding, type Shell } from './ui';
import {
  hasToken,
  setStoredToken,
  clearStoredToken,
  getActiveToken,
} from './config';

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
  wireControls(shell, globe);

  try {
    setLoading(shell, true, 'Loading photoreal tiles');
    await globe.initPhotoreal();
    setLoading(shell, false);
    // Cinematic arrival at the first destination once the surface is ready.
    globe.flyToPlace(PLACES[0], 4.2);
  } catch (err) {
    handleTokenFailure(root, err);
  }
}

function wireControls(shell: Shell, globe: Globe): void {
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
    globe.flyWholePlanet(2.6);
    collapseSearch(shell);
  });

  // Mode toggle
  const setMode = async (mode: SceneMode) => {
    const isPhotoreal = mode === 'photoreal';
    shell.modePhotoreal.classList.toggle('is-active', isPhotoreal);
    shell.modeTerrain.classList.toggle('is-active', !isPhotoreal);
    shell.modeThumb.style.transform = isPhotoreal ? 'translateX(0)' : 'translateX(100%)';
    if (mode === 'terrain') setLoading(shell, true, 'Loading world terrain');
    try {
      await globe.setMode(mode);
    } finally {
      setLoading(shell, false);
    }
  };
  shell.modePhotoreal.addEventListener('click', () => void setMode('photoreal'));
  shell.modeTerrain.addEventListener('click', () => void setMode('terrain'));

  // Search
  wireSearch(shell, globe);
}

function wireSearch(shell: Shell, globe: Globe): void {
  let token = 0;
  let debounce: number | undefined;

  const render = (items: { displayName: string; run: () => void }[]) => {
    shell.searchResults.replaceChildren();
    if (items.length === 0) {
      shell.searchResults.classList.remove('is-open');
      return;
    }
    for (const item of items) {
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'search-result';
      row.textContent = item.displayName;
      row.addEventListener('click', () => {
        item.run();
        collapseSearch(shell);
        shell.searchInput.blur();
      });
      shell.searchResults.append(row);
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
        results.slice(0, 6).map((r) => ({
          displayName: r.displayName,
          run: () => globe.flyToDestination(r.destination),
        })),
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
