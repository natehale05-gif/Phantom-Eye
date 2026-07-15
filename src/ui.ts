import { PLACES, type Place } from './places';
import type { ManeuverKind } from './routing';

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
  destinationsWrap: HTMLElement;
  destinationsRail: HTMLElement;
  homeButton: HTMLButtonElement;
  locateButton: HTMLButtonElement;
  navPanel: HTMLElement;
  guidance: HTMLElement;
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
    placeholder: 'Search or get directions',
    autocomplete: 'off',
    spellcheck: false,
  });
  const searchResults = el('div', { class: 'search-results' });
  const searchBar = el('div', { class: 'search-bar glass' }, [
    el('div', { class: 'search-icon', innerHTML: icons.search }),
    searchInput,
    searchResults,
  ]);

  const topBar = el('div', { class: 'top-bar' }, [brand, searchBar]);

  // --- Destinations rail ---
  const destinationsRail = el('div', { class: 'destinations' });
  for (const place of PLACES) destinationsRail.append(destinationCard(place));
  const destinationsWrap = el('div', { class: 'destinations-wrap' }, [
    el('div', { class: 'destinations-title', textContent: 'Destinations' }),
    destinationsRail,
  ]);

  // --- Side controls (globe reset + my location) ---
  const homeButton = el('button', {
    class: 'orb-button glass',
    type: 'button',
    title: 'View the whole planet',
    innerHTML: icons.globe,
  });
  const locateButton = el('button', {
    class: 'orb-button glass',
    type: 'button',
    title: 'My location',
    innerHTML: icons.locate,
  });
  const sideControls = el('div', { class: 'side-controls' }, [locateButton, homeButton]);

  // --- Navigation bottom sheet + guidance banner (filled dynamically) ---
  const navPanel = el('div', { class: 'nav-panel' });
  const guidance = el('div', { class: 'guidance' });

  // --- Loading ---
  const loadingLabel = el('div', { class: 'loading-label', textContent: 'Loading' });
  const loading = el('div', { class: 'loading' }, [
    el('div', { class: 'loading-ring' }),
    loadingLabel,
  ]);

  const root = el('div', { class: 'app-shell' }, [
    cesiumContainer,
    el('div', { class: 'vignette' }),
    topBar,
    destinationsWrap,
    sideControls,
    navPanel,
    guidance,
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
    destinationsWrap,
    destinationsRail,
    homeButton,
    locateButton,
    navPanel,
    guidance,
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
  const submit = el('button', { class: 'token-submit', type: 'button', textContent: 'Launch' });
  const error = el('div', { class: 'token-error' });

  const card = el('div', { class: 'onboarding-card glass' }, [
    el('div', { class: 'onboarding-mark', innerHTML: icons.globe }),
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

  const overlay = el('div', { class: 'onboarding' }, [el('div', { class: 'onboarding-bg' }), card]);
  mount.append(overlay);
  return { overlay, input, submit, error };
}

/** Inline SVG for a maneuver arrow. */
export function maneuverIcon(kind: ManeuverKind): string {
  return icons.maneuver[kind] ?? icons.maneuver.straight;
}

const arrow = (d: string) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;

const icons = {
  search:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>`,
  globe:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><line x1="3" y1="12" x2="21" y2="12"/></svg>`,
  locate:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="4"/><line x1="12" y1="2" x2="12" y2="5"/><line x1="12" y1="19" x2="12" y2="22"/><line x1="2" y1="12" x2="5" y2="12"/><line x1="19" y1="12" x2="22" y2="12"/></svg>`,
  directions:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 2 22 12 12 22 2 12Z"/><path d="M9 13v-2a2 2 0 0 1 2-2h4"/><path d="M13 6l3 3-3 3"/></svg>`,
  maneuver: {
    depart: arrow('<circle cx="12" cy="12" r="4"/>'),
    straight: arrow('<line x1="12" y1="20" x2="12" y2="5"/><path d="M6 11l6-6 6 6"/>'),
    left: arrow('<path d="M20 18v-4a4 4 0 0 0-4-4H6"/><path d="M10 6L4 10l6 4"/>'),
    right: arrow('<path d="M4 18v-4a4 4 0 0 1 4-4h10"/><path d="M14 6l6 4-6 4"/>'),
    'slight-left': arrow('<path d="M18 20V12a4 4 0 0 0-4-4H8"/><path d="M11 4L6 8l5 4"/>'),
    'slight-right': arrow('<path d="M6 20V12a4 4 0 0 1 4-4h6"/><path d="M13 4l5 4-5 4"/>'),
    'sharp-left': arrow('<path d="M18 20a8 8 0 0 0-8-8H6"/><path d="M10 7L4 12l6 5"/>'),
    'sharp-right': arrow('<path d="M6 20a8 8 0 0 1 8-8h4"/><path d="M14 7l6 5-6 5"/>'),
    uturn: arrow('<path d="M8 20V9a4 4 0 0 1 8 0v3"/><path d="M12 8L8 4 4 8"/>'),
    roundabout: arrow('<circle cx="12" cy="10" r="5"/><line x1="12" y1="22" x2="12" y2="15"/>'),
    merge: arrow('<path d="M12 20v-6"/><path d="M12 14c0-5 4-7 8-8"/><path d="M8 8l4-4 4 4"/>'),
    ramp: arrow('<path d="M6 20c8 0 12-5 12-14"/><path d="M14 4h4v4"/>'),
    arrive: arrow('<path d="M12 21s-7-6.5-7-11a7 7 0 0 1 14 0c0 4.5-7 11-7 11Z"/><circle cx="12" cy="10" r="2"/>'),
  } as Record<ManeuverKind, string>,
};
