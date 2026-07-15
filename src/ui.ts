import type { ManeuverKind } from './routing';
import { CATEGORIES } from './categories';

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
  menuButton: HTMLButtonElement;
  menu: HTMLElement;
  menuLocate: HTMLButtonElement;
  menuWaypoint: HTMLButtonElement;
  menuWaypoints: HTMLButtonElement;
  menuRecord: HTMLButtonElement;
  menuHome: HTMLButtonElement;
  categories: HTMLElement;
  navPanel: HTMLElement;
  waypointsPanel: HTMLElement;
  placeCard: HTMLElement;
  guidance: HTMLElement;
  tripBar: HTMLElement;
  hud: HTMLElement;
  loading: HTMLElement;
  loadingLabel: HTMLElement;
}

/** Builds the main application chrome and returns handles to interactive nodes. */
export function buildShell(mount: HTMLElement): Shell {
  const cesiumContainer = el('div', { id: 'cesiumContainer', class: 'cesium-container' });
  const creditContainer = el('div', { class: 'credit-container' });

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

  // --- Menu dropdown (all tools) next to the search bar ---
  const item = (icon: string, label: string) =>
    el('button', { class: 'menu-item', type: 'button' }, [
      el('span', { class: 'menu-item-icon', innerHTML: icon }),
      el('span', { class: 'menu-item-label', textContent: label }),
    ]);

  const menuLocate = item(icons.locate, 'My Location');
  const menuWaypoint = item(icons.pin, 'Drop Waypoint');
  const menuWaypoints = item(icons.list, 'Waypoints');
  const menuRecord = item(icons.record, 'Record Track');
  const menuHome = item(icons.globe, 'Whole Planet');
  const menu = el('div', { class: 'menu glass' }, [
    menuLocate,
    menuWaypoint,
    menuWaypoints,
    menuRecord,
    menuHome,
  ]);
  const menuButton = el('button', {
    class: 'menu-button glass',
    type: 'button',
    title: 'Tools',
    innerHTML: icons.menu,
  });
  const menuWrap = el('div', { class: 'menu-wrap' }, [menuButton, menu]);

  const searchRow = el('div', { class: 'search-row' }, [searchBar, menuWrap]);

  // --- Category chips (Find nearby: Food, Groceries, Hotels, …) ---
  const categories = el(
    'div',
    { class: 'categories' },
    CATEGORIES.map((c) =>
      el('button', { class: 'chip', type: 'button' }, [
        el('span', {
          class: 'chip-icon',
          innerHTML: `<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${c.glyph}</svg>`,
        }),
        el('span', { class: 'chip-label', textContent: c.label }),
      ]),
    ),
  );
  CATEGORIES.forEach((c, i) => {
    const chip = categories.children[i] as HTMLElement;
    chip.dataset.cat = c.id;
    chip.style.setProperty('--chip-color', c.color);
  });

  const topBar = el('div', { class: 'top-bar' }, [searchRow, categories]);

  // --- Bottom sheets + guidance banner + HUD (filled dynamically) ---
  const navPanel = el('div', { class: 'nav-panel' });
  const waypointsPanel = el('div', { class: 'nav-panel' });
  const placeCard = el('div', { class: 'place-card-wrap' });
  const guidance = el('div', { class: 'guidance' });
  const tripBar = el('div', { class: 'trip-bar' });
  const hud = el('div', { class: 'hud' });

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
    navPanel,
    waypointsPanel,
    placeCard,
    guidance,
    tripBar,
    hud,
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
    menuButton,
    menu,
    menuLocate,
    menuWaypoint,
    menuWaypoints,
    menuRecord,
    menuHome,
    categories,
    navPanel,
    waypointsPanel,
    placeCard,
    guidance,
    tripBar,
    hud,
    loading,
    loadingLabel,
  };
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
  pin:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 21s-6-5.7-6-10a6 6 0 0 1 12 0c0 4.3-6 10-6 10Z"/><circle cx="12" cy="11" r="2.2"/></svg>`,
  list:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><line x1="9" y1="6" x2="20" y2="6"/><line x1="9" y1="12" x2="20" y2="12"/><line x1="9" y1="18" x2="20" y2="18"/><circle cx="4.5" cy="6" r="1.2" fill="currentColor" stroke="none"/><circle cx="4.5" cy="12" r="1.2" fill="currentColor" stroke="none"/><circle cx="4.5" cy="18" r="1.2" fill="currentColor" stroke="none"/></svg>`,
  record:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/></svg>`,
  menu:
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><circle cx="5.5" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="18.5" cy="12" r="1.4" fill="currentColor" stroke="none"/></svg>`,
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
