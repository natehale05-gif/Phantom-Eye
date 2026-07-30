/// One OSM `key=value` tag pair used to query a category.
final class OsmTag {
  const OsmTag(this.key, this.value);
  final String key;
  final String value;

  @override
  String toString() => '$key=$value';
}

/// A searchable place category, matching the chips in the legacy UI.
///
/// `colorHex` is kept as a string rather than a Flutter `Color` so this stays
/// in the Flutter-free domain layer; the UI package converts it.
final class Category {
  const Category({
    required this.id,
    required this.label,
    required this.colorHex,
    required this.osmTags,
    required this.keywords,
  });

  final String id;
  final String label;
  final String colorHex;

  /// Tag pairs to query. Each becomes one node clause and one way clause.
  final List<OsmTag> osmTags;

  /// Free-text terms that should resolve to this category.
  final List<String> keywords;
}

/// Fallback pin colour for results with no category.
///
/// Ported from `DEFAULT_PIN_COLOR` in `src/categories.ts`.
const String kDefaultPinColorHex = '#FF3B30';

/// Filler words stripped before category matching, so "best coffee near me"
/// still resolves to Coffee.
///
/// Ported from `FILLER` in `src/categories.ts:192`. Order matters inside the
/// alternation only insofar as the regex is applied globally.
final RegExp _filler = RegExp(
  r'\b(near ?me|near ?by|around ?me|close ?by|closest|nearest|places?|spots?'
  r'|good|best|cheap|open|the|a|some)\b',
);

/// Everything outside this set is replaced with a space.
///
/// Note this **strips digits**, so "76 gas" reduces to "gas" — preserved from
/// the original, where it still matches the Gas category via the remaining
/// word. Accented Latin letters are kept so "café" survives.
final RegExp _nonLetters = RegExp(r'[^a-zà-ÿ\s]');

final RegExp _whitespace = RegExp(r'\s+');

/// The 13 place categories, in declaration order — which is also match
/// precedence, since matching is first-match-wins.
///
/// Generated from `CATEGORIES` in `src/categories.ts` rather than transcribed
/// by hand, so ids, labels, colours, OSM tag pairs and keyword lists cannot
/// drift from the original. The glyph SVGs are deliberately omitted: they
/// belong to the UI layer, not here.
const List<Category> kCategories = [
  Category(
    id: 'food',
    label: 'Food',
    colorHex: '#FF9500',
    osmTags: [OsmTag('amenity', 'restaurant'), OsmTag('amenity', 'fast_food')],
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
  ),
  Category(
    id: 'coffee',
    label: 'Coffee',
    colorHex: '#AC7F5E',
    osmTags: [OsmTag('amenity', 'cafe')],
    keywords: [
      'coffee',
      'cafe',
      'café',
      'espresso',
      'latte',
      'cappuccino',
      'breakfast',
    ],
  ),
  Category(
    id: 'groceries',
    label: 'Groceries',
    colorHex: '#FFB340',
    osmTags: [
      OsmTag('shop', 'supermarket'),
      OsmTag('shop', 'convenience'),
      OsmTag('shop', 'grocery'),
    ],
    keywords: ['groceries', 'grocery', 'supermarket', 'market', 'food store'],
  ),
  Category(
    id: 'gas',
    label: 'Gas',
    colorHex: '#5E5CE6',
    osmTags: [OsmTag('amenity', 'fuel')],
    keywords: ['gas', 'fuel', 'petrol', 'gasoline', 'gas station'],
  ),
  Category(
    id: 'hotels',
    label: 'Hotels',
    colorHex: '#BF5AF2',
    osmTags: [OsmTag('tourism', 'hotel'), OsmTag('tourism', 'motel')],
    keywords: [
      'hotel',
      'hotels',
      'motel',
      'lodging',
      'lodge',
      'inn',
      'stay',
      'accommodation',
    ],
  ),
  Category(
    id: 'shopping',
    label: 'Shopping',
    colorHex: '#FF2D55',
    osmTags: [
      OsmTag('shop', 'mall'),
      OsmTag('shop', 'department_store'),
      OsmTag('shop', 'clothes'),
    ],
    keywords: [
      'shopping',
      'mall',
      'shops',
      'store',
      'stores',
      'outlet',
      'clothes',
    ],
  ),
  Category(
    id: 'parks',
    label: 'Parks',
    colorHex: '#34C759',
    osmTags: [OsmTag('leisure', 'park')],
    keywords: ['park', 'parks', 'playground', 'green space'],
  ),
  Category(
    id: 'bars',
    label: 'Bars',
    colorHex: '#64D2FF',
    osmTags: [OsmTag('amenity', 'bar'), OsmTag('amenity', 'pub')],
    keywords: [
      'bar',
      'bars',
      'pub',
      'pubs',
      'drinks',
      'nightlife',
      'brewery',
      'tavern',
      'cocktails',
    ],
  ),
  Category(
    id: 'surf',
    label: 'Surf',
    colorHex: '#00C7BE',
    osmTags: [OsmTag('sport', 'surfing'), OsmTag('natural', 'beach')],
    keywords: ['surf', 'surfing', 'waves', 'beach', 'beaches', 'surf spot'],
  ),
  Category(
    id: 'ski',
    label: 'Ski',
    colorHex: '#5AC8FA',
    osmTags: [OsmTag('sport', 'skiing'), OsmTag('landuse', 'winter_sports')],
    keywords: [
      'ski',
      'skiing',
      'snowboard',
      'snowboarding',
      'slopes',
      'ski resort',
    ],
  ),
  Category(
    id: 'climb',
    label: 'Climb',
    colorHex: '#AF52DE',
    osmTags: [OsmTag('sport', 'climbing')],
    keywords: ['climb', 'climbing', 'bouldering', 'rock climbing'],
  ),
  Category(
    id: 'golf',
    label: 'Golf',
    colorHex: '#30D158',
    osmTags: [OsmTag('leisure', 'golf_course')],
    keywords: ['golf', 'golf course', 'driving range'],
  ),
  Category(
    id: 'camp',
    label: 'Camp',
    colorHex: '#FF9500',
    osmTags: [
      OsmTag('tourism', 'camp_site'),
      OsmTag('tourism', 'wilderness_hut'),
    ],
    keywords: ['camp', 'camping', 'campground', 'campsite', 'campsites'],
  ),
];

/// Look up a category by id. Null id or unknown id yields null.
///
/// Ported from `categoryById` in `src/categories.ts:188`.
Category? categoryById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final c in kCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// Normalise a free-text query for category matching.
///
/// Exposed for testing so the stripping stages can be checked directly.
String normalizeCategoryQuery(String query) => query
    .toLowerCase()
    .replaceAll(_filler, ' ')
    .replaceAll(_nonLetters, ' ')
    .replaceAll(_whitespace, ' ')
    .trim();

/// Map a free-text query to a category, so typing "dinner" or "gas" behaves
/// like tapping the matching chip.
///
/// Returns null when the query looks like a specific place name, which the
/// caller then hands to geocoding instead.
///
/// Ported from `matchCategory` in `src/categories.ts:199`. Two passes, in this
/// order:
///  1. **whole phrase** — the normalised query equals a label or is one of a
///     category's keywords. This is what lets multi-word keywords such as
///     `gas station` and `food store` match at all.
///  2. **tokens** — only for queries of three words or fewer, any single token
///     matching a label or keyword. The length cap keeps a long place name
///     containing an incidental word (say "The Coffee Manufactory on Bryant")
///     from being hijacked into a category search.
///
/// Both passes scan [kCategories] in order and return the first hit.
Category? matchCategory(String query) {
  final q = normalizeCategoryQuery(query);
  if (q.isEmpty) return null;

  for (final c in kCategories) {
    if (c.label.toLowerCase() == q || c.keywords.contains(q)) return c;
  }

  final tokens = q.split(' ');
  if (tokens.length <= 3) {
    for (final c in kCategories) {
      final set = {c.label.toLowerCase(), ...c.keywords};
      if (tokens.any(set.contains)) return c;
    }
  }
  return null;
}
