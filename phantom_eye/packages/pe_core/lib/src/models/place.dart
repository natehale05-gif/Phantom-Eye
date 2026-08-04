import '../geo/lng_lat.dart';

/// The three OpenStreetMap primitive types.
///
/// Mirrors `OsmType` in `src/geocode.ts:10`. Overpass spells these out in
/// full (`node`/`way`/`relation`) while Photon abbreviates them to a single
/// letter, so both spellings are parsed here rather than at each call site.
enum OsmType {
  node('node', 'N'),
  way('way', 'W'),
  relation('relation', 'R');

  const OsmType(this.osmName, this.photonLetter);

  /// How Overpass and the Overpass query language spell it.
  final String osmName;

  /// How Photon's `osm_type` property spells it.
  final String photonLetter;

  /// Parse either spelling. Returns null for anything unrecognised.
  static OsmType? parse(Object? value) {
    if (value is! String || value.isEmpty) return null;
    for (final t in values) {
      if (value == t.osmName || value == t.photonLetter) return t;
    }
    return null;
  }
}

/// Extra Apple-Maps-style details for a place.
///
/// Mirrors `PlaceDetails` in `src/geocode.ts:13`. These may arrive with the
/// search result (Overpass returns tags inline) or be fetched lazily
/// afterwards (Photon does not return contact tags), which is why every field
/// is nullable and why [merge] exists.
final class PlaceDetails {
  const PlaceDetails({
    this.phone,
    this.website,
    this.openingHours,
    this.address,
  });

  final String? phone;
  final String? website;
  final String? openingHours;
  final String? address;

  bool get isEmpty =>
      phone == null &&
      website == null &&
      openingHours == null &&
      address == null;

  /// Overlay [other]'s non-null fields onto this one.
  ///
  /// Used when a lazily-fetched detail lookup enriches a result that came
  /// from the text geocoder: anything the lookup did not find must not erase
  /// what the search already knew.
  PlaceDetails merge(PlaceDetails other) => PlaceDetails(
    phone: other.phone ?? phone,
    website: other.website ?? website,
    openingHours: other.openingHours ?? openingHours,
    address: other.address ?? address,
  );
}

/// A search or nearby result.
///
/// Mirrors `PlaceResult` in `src/geocode.ts:22`, which spread [PlaceDetails]
/// into the same object; here they are composed instead, so "what the search
/// returned" and "what a detail lookup added" stay distinguishable.
final class Place {
  const Place({
    required this.name,
    required this.detail,
    required this.position,
    this.category = '',
    this.categoryId,
    this.osmType,
    this.osmId,
    this.details = const PlaceDetails(),
  });

  /// Primary label, e.g. the POI name or `123 Main St`.
  final String name;

  /// Secondary label under [name] in the results list.
  final String detail;

  final LngLat position;

  /// Free-form kind, e.g. Photon's `osm_value` or a category label.
  final String category;

  /// Set only when this came from a category chip search.
  final String? categoryId;

  final OsmType? osmType;
  final int? osmId;

  final PlaceDetails details;

  /// Stable identity for deduping, when this place came from OSM.
  ///
  /// Null when either half is missing — callers must then fall back to a
  /// weaker key rather than treating all such places as equal.
  String? get osmKey =>
      (osmType != null && osmId != null) ? '${osmType!.osmName}/$osmId' : null;

  /// Parse a stored place, or null if it is not usable.
  ///
  /// The JSON is **flat**, with the [PlaceDetails] fields spread alongside the
  /// rest, because that is the shape the legacy app wrote to `localStorage`
  /// (`PlaceResult` extended `PlaceDetails` rather than composing it). Keeping
  /// it means saved recents survive a migration.
  ///
  /// Returning null rather than throwing lets one corrupt entry be dropped
  /// while the rest of a stored list survives — the legacy loader validated
  /// only that the outer value was an array, so a truncated write produced a
  /// row with no coordinate that broke rendering.
  static Place? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final lon = json['lon'];
    final lat = json['lat'];
    if (name is! String || name.isEmpty) return null;
    if (lon is! num || lat is! num || !lon.isFinite || !lat.isFinite) {
      return null;
    }
    return Place(
      name: name,
      detail: json['detail'] is String ? json['detail'] as String : '',
      position: LngLat(lon.toDouble(), lat.toDouble()),
      category: json['category'] is String ? json['category'] as String : '',
      categoryId: json['categoryId'] is String
          ? json['categoryId'] as String
          : null,
      osmType: OsmType.parse(json['osmType']),
      osmId: json['osmId'] is num ? (json['osmId'] as num).toInt() : null,
      details: PlaceDetails(
        phone: json['phone'] is String ? json['phone'] as String : null,
        website: json['website'] is String ? json['website'] as String : null,
        openingHours: json['openingHours'] is String
            ? json['openingHours'] as String
            : null,
        address: json['address'] is String ? json['address'] as String : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'detail': detail,
    'lon': position.lon,
    'lat': position.lat,
    'category': category,
    'categoryId': ?categoryId,
    'osmType': ?osmType?.osmName,
    'osmId': ?osmId,
    'phone': ?details.phone,
    'website': ?details.website,
    'openingHours': ?details.openingHours,
    'address': ?details.address,
  };

  Place withDetails(PlaceDetails extra) => Place(
    name: name,
    detail: detail,
    position: position,
    category: category,
    categoryId: categoryId,
    osmType: osmType,
    osmId: osmId,
    details: details.merge(extra),
  );

  @override
  String toString() => 'Place($name @ $position)';
}
