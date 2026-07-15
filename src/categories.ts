/**
 * Location categories — the "Find nearby" chips (Food, Groceries, Hotels, …),
 * modeled on Apple Maps. Each category carries a color + glyph for its map pin
 * and a set of OpenStreetMap tag filters used to query nearby places.
 */

export interface Category {
  id: string;
  label: string;
  color: string;
  /** Inner SVG (24×24, stroke-based) drawn inside the pin head. */
  glyph: string;
  /** OpenStreetMap [key, value] tag pairs to search for. */
  osm: [string, string][];
  /**
   * Words a user might type to mean this category — so searching "dinner",
   * "lunch", or "coffee" pulls up the matching nearby places, Apple-Maps-style.
   */
  keywords: string[];
}

// A neutral pin for plain search results (Apple's red "dropped" pin).
export const DEFAULT_PIN_COLOR = '#FF3B30';

export const CATEGORIES: Category[] = [
  {
    id: 'food',
    label: 'Food',
    color: '#FF9500',
    glyph:
      '<path d="M6 3v5a2 2 0 0 0 4 0V3"/><path d="M8 8v13"/><path d="M16 3c-1.6 1-2.2 3-2.2 6s2.2 3 2.2 3v9"/>',
    osm: [
      ['amenity', 'restaurant'],
      ['amenity', 'fast_food'],
    ],
    keywords: [
      'food',
      'restaurant',
      'restaurants',
      'dinner',
      'lunch',
      'brunch',
      'dining',
      'eat',
      'meal',
      'takeout',
      'diner',
      'pizza',
      'burger',
      'burgers',
      'sushi',
      'tacos',
      'mexican',
      'italian',
      'chinese',
      'thai',
      'indian',
      'sandwich',
      'bbq',
      'steakhouse',
    ],
  },
  {
    id: 'coffee',
    label: 'Coffee',
    color: '#AC7F5E',
    glyph:
      '<path d="M5 8h11v4a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5V8Z"/><path d="M16 9h2.5a2.5 2.5 0 0 1 0 5H16"/><path d="M8 3v2"/><path d="M12 3v2"/>',
    osm: [['amenity', 'cafe']],
    keywords: ['coffee', 'cafe', 'café', 'espresso', 'latte', 'cappuccino', 'breakfast'],
  },
  {
    id: 'groceries',
    label: 'Groceries',
    color: '#FFB340',
    glyph:
      '<circle cx="9" cy="20" r="1.4"/><circle cx="17" cy="20" r="1.4"/><path d="M3 4h2l2 11h11"/><path d="M7 8h13l-1.6 6"/>',
    osm: [
      ['shop', 'supermarket'],
      ['shop', 'convenience'],
      ['shop', 'grocery'],
    ],
    keywords: ['groceries', 'grocery', 'supermarket', 'market', 'food store'],
  },
  {
    id: 'gas',
    label: 'Gas',
    color: '#5E5CE6',
    glyph:
      '<path d="M5 21V6a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v15"/><path d="M4 21h11"/><path d="M7 9h5"/><path d="M14 9l3 3v6a2 2 0 0 0 3 0V10l-3-3"/>',
    osm: [['amenity', 'fuel']],
    keywords: ['gas', 'fuel', 'petrol', 'gasoline', 'gas station'],
  },
  {
    id: 'hotels',
    label: 'Hotels',
    color: '#BF5AF2',
    glyph:
      '<path d="M3 19V9"/><path d="M3 13h13a5 5 0 0 1 5 5v1"/><path d="M21 19v-2"/><circle cx="7.5" cy="11" r="1.6"/>',
    osm: [
      ['tourism', 'hotel'],
      ['tourism', 'motel'],
    ],
    keywords: ['hotel', 'hotels', 'motel', 'lodging', 'lodge', 'inn', 'stay', 'accommodation'],
  },
  {
    id: 'shopping',
    label: 'Shopping',
    color: '#FF2D55',
    glyph: '<path d="M6 8h12l1 12H5L6 8Z"/><path d="M9 8a3 3 0 0 1 6 0"/>',
    osm: [
      ['shop', 'mall'],
      ['shop', 'department_store'],
      ['shop', 'clothes'],
    ],
    keywords: ['shopping', 'mall', 'shops', 'store', 'stores', 'outlet', 'clothes'],
  },
  {
    id: 'parks',
    label: 'Parks',
    color: '#34C759',
    glyph: '<path d="M12 3 6 12h3l-3 5h12l-3-5h3L12 3Z"/><path d="M12 17v4"/>',
    osm: [['leisure', 'park']],
    keywords: ['park', 'parks', 'playground', 'green space'],
  },
  {
    id: 'bars',
    label: 'Bars',
    color: '#64D2FF',
    glyph: '<path d="M5 4h14l-7 8-7-8Z"/><path d="M12 12v6"/><path d="M8 21h8"/>',
    osm: [
      ['amenity', 'bar'],
      ['amenity', 'pub'],
    ],
    keywords: ['bar', 'bars', 'pub', 'pubs', 'drinks', 'nightlife', 'brewery', 'tavern', 'cocktails'],
  },
  {
    id: 'surf',
    label: 'Surf',
    color: '#00C7BE',
    glyph: '<path d="M3 17c4 0 4-2 8-2s4 2 8 2"/><path d="M3 21c4 0 4-2 8-2s4 2 8 2"/><path d="M14 4c3 3 3 7 0 11"/>',
    osm: [
      ['sport', 'surfing'],
      ['natural', 'beach'],
    ],
    keywords: ['surf', 'surfing', 'waves', 'beach', 'beaches', 'surf spot'],
  },
  {
    id: 'ski',
    label: 'Ski',
    color: '#5AC8FA',
    glyph: '<path d="M4 20l16-6"/><path d="M6 19l14-5"/><circle cx="16" cy="5" r="1.6"/><path d="M14 8l2 3 3 1"/>',
    osm: [
      ['sport', 'skiing'],
      ['landuse', 'winter_sports'],
    ],
    keywords: ['ski', 'skiing', 'snowboard', 'snowboarding', 'slopes', 'ski resort'],
  },
  {
    id: 'climb',
    label: 'Climb',
    color: '#AF52DE',
    glyph: '<circle cx="14" cy="5" r="1.6"/><path d="M13 8l-4 3 3 3-2 6"/><path d="M12 14l5 2 3-2"/><path d="M9 11l-4 1"/>',
    osm: [['sport', 'climbing']],
    keywords: ['climb', 'climbing', 'bouldering', 'rock climbing'],
  },
  {
    id: 'golf',
    label: 'Golf',
    color: '#30D158',
    glyph: '<path d="M11 3v14"/><path d="M11 5l6 2-6 2"/><path d="M6 21c1-1.5 3-2 5-2s4 .5 5 2"/>',
    osm: [['leisure', 'golf_course']],
    keywords: ['golf', 'golf course', 'driving range'],
  },
  {
    id: 'camp',
    label: 'Camp',
    color: '#FF9500',
    glyph: '<path d="M12 4 3 20h18L12 4Z"/><path d="M12 4v16"/>',
    osm: [
      ['tourism', 'camp_site'],
      ['tourism', 'wilderness_hut'],
    ],
    keywords: ['camp', 'camping', 'campground', 'campsite', 'campsites'],
  },
];

export function categoryById(id: string | undefined): Category | undefined {
  return id ? CATEGORIES.find((c) => c.id === id) : undefined;
}

const FILLER = /\b(near ?me|near ?by|around ?me|close ?by|closest|nearest|places?|spots?|good|best|cheap|open|the|a|some)\b/g;

/**
 * Map a free-text query to a category so "food", "dinner", "lunch", "coffee",
 * "gas", etc. behave like tapping the matching category chip. Returns undefined
 * when the query looks like a specific place name (handled by geocoding).
 */
export function matchCategory(query: string): Category | undefined {
  const q = query
    .toLowerCase()
    .replace(FILLER, ' ')
    .replace(/[^a-zà-ÿ\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!q) return undefined;

  // Whole-phrase match first (handles "gas station", "ski resort", …).
  for (const c of CATEGORIES) {
    if (c.label.toLowerCase() === q || c.keywords.includes(q)) return c;
  }
  // Otherwise, a short query whose words include a category keyword.
  const tokens = q.split(' ');
  if (tokens.length <= 3) {
    for (const c of CATEGORIES) {
      const set = new Set([c.label.toLowerCase(), ...c.keywords]);
      if (tokens.some((t) => set.has(t))) return c;
    }
  }
  return undefined;
}
