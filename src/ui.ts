import { PLACES, type Place } from './places';

/** Tiny hyperscript helper. */
export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  props: Partial<HTMLElementTagNameMap[K]> & { class?: string } = {},
  children: (Node | string)[] = [],
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  const { class: className, ...rest } = props as Record<string, unknown> & {
    class?: string;
  };
  if (className) node.className = className;
  Object.assign(node, rest);
  for (const child of children) {
    node.append(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

export interface Shell {
  root: HTMLElement;
  cesiumContainer: HTMLElement;
  creditContainer: HTMLElement;
  searchInput: HTMLInputElement;
  searchResults: HTMLElement;
  destinationsRail: HTMLElement;
  modePhotoreal: HTMLButtonElement;
  modeTerrain: HTMLButtonElement;
  modeThumb: HTMLElement;
  homeButton: HTMLButtonElement;
  loading: HTMLElement;
  loadingLabel: HTMLElement;
}

/** Builds the main application chrome and returns handles to interactive nodes. */
export function buildShell(mount: HTMLElement): Shell {
  const cesiumContainer = el('div', { id: 'cesiumContainer', class: 'cesium-container' });
  const creditContainer = el('div', { class: 'credit-container' });

  const brand = el('div', { class: 'brand' }, [
    el('span', { class: 'brand-dot' }),
    el('span', { class: 'brand-name', textContent: 'Phantom Eye' }),
  ]);

  // --- Search ---
  const searchInput = el('input', {
    class: 'search-input',
    type: 'text',
    placeholder: 'Search anywhere on Earth',
    autocomplete: 'off',
    spellcheck: false,
  });
  const searchResults = el('div', { class: 'search-results' });
  const searchBar = el('div', { class: 'search-bar glass' }, [
    el('div', { class: 'search-icon', innerHTML: searchIcon() }),
    searchInput,
    searchResults,
  ]);

  // --- Mode segmented control ---
  const modeThumb = el('div', { class: 'segmented-thumb' });
  const modePhotoreal = el('button', {
    class: 'segmented-option is-active',
    type: 'button',
    textContent: 'Photoreal',
  });
  const modeTerrain = el('button', {
    class: 'segmented-option',
    type: 'button',
    textContent: 'Terrain',
  });
  const segmented = el('div', { class: 'segmented glass' }, [
    modeThumb,
    modePhotoreal,
    modeTerrain,
  ]);

  const topBar = el('div', { class: 'top-bar' }, [brand, searchBar, segmented]);

  // --- Destinations rail ---
  const destinationsRail = el('div', { class: 'destinations' });
  for (const place of PLACES) {
    destinationsRail.append(destinationCard(place));
  }
  const railWrap = el('div', { class: 'destinations-wrap' }, [
    el('div', { class: 'destinations-title', textContent: 'Destinations' }),
    destinationsRail,
  ]);

  // --- Home / globe reset ---
  const homeButton = el('button', {
    class: 'orb-button glass',
    type: 'button',
    title: 'View the whole planet',
    innerHTML: globeIcon(),
  });
  const sideControls = el('div', { class: 'side-controls' }, [homeButton]);

  // --- Loading ---
  const loadingLabel = el('div', { class: 'loading-label', textContent: 'Loading terrain' });
  const loading = el('div', { class: 'loading' }, [
    el('div', { class: 'loading-ring' }),
    loadingLabel,
  ]);

  const root = el('div', { class: 'app-shell' }, [
    cesiumContainer,
    el('div', { class: 'vignette' }),
    topBar,
    railWrap,
    sideControls,
    creditContainer,
    loading,
  ]);

  mount.append(root);

  return {
    root,
    cesiumContainer,
    creditContainer,
    searchInput,
    searchResults,
    destinationsRail,
    modePhotoreal,
    modeTerrain,
    modeThumb,
    homeButton,
    loading,
    loadingLabel,
  };
}

function destinationCard(place: Place): HTMLButtonElement {
  const card = el('button', { class: 'destination-card', type: 'button' }, [
    el('span', { class: 'destination-name', textContent: place.name }),
    el('span', { class: 'destination-region', textContent: place.region }),
  ]);
  card.dataset.placeId = place.id;
  return card;
}

/** Onboarding overlay for entering a Cesium ion access token. */
export interface Onboarding {
  overlay: HTMLElement;
  input: HTMLInputElement;
  submit: HTMLButtonElement;
  error: HTMLElement;
}

export function buildOnboarding(mount: HTMLElement, prefill = ''): Onboarding {
  const input = el('input', {
    class: 'token-input',
    type: 'password',
    placeholder: 'Paste your Cesium ion access token',
    value: prefill,
    autocomplete: 'off',
    spellcheck: false,
  });
  const submit = el('button', {
    class: 'token-submit',
    type: 'button',
    textContent: 'Launch',
  });
  const error = el('div', { class: 'token-error' });

  const card = el('div', { class: 'onboarding-card glass' }, [
    el('div', { class: 'onboarding-mark', innerHTML: globeIcon() }),
    el('h1', { class: 'onboarding-title', textContent: 'Phantom Eye' }),
    el('p', {
      class: 'onboarding-sub',
      textContent: 'The planet in photorealistic 3D. Bring your Cesium ion key to begin.',
    }),
    el('div', { class: 'token-row' }, [input, submit]),
    error,
    el('a', {
      class: 'token-help',
      href: 'https://ion.cesium.com/tokens',
      target: '_blank',
      rel: 'noreferrer noopener',
      textContent: 'Get a free Cesium ion token →',
    }),
  ]);

  const overlay = el('div', { class: 'onboarding' }, [
    el('div', { class: 'onboarding-bg' }),
    card,
  ]);
  mount.append(overlay);
  return { overlay, input, submit, error };
}

function searchIcon(): string {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>`;
}

function globeIcon(): string {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><line x1="3" y1="12" x2="21" y2="12"/></svg>`;
}
