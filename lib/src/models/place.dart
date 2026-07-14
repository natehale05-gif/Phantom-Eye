import 'geo_point.dart';

enum PlaceCategory {
  address,
  business,
  food,
  gas,
  parking,
  lodging,
  trailhead,
  summit,
  campground,
  water,
  other,
}

/// A search result / point of interest, as returned by the Photon geocoder
/// or hand-placed by the user (waypoints reuse this for display purposes).
class Place {
  const Place({
    required this.name,
    required this.point,
    this.subtitle,
    this.category = PlaceCategory.other,
    this.osmId,
  });

  final String name;
  final String? subtitle;
  final GeoPoint point;
  final PlaceCategory category;
  final String? osmId;

  factory Place.fromPhotonFeature(Map<String, dynamic> feature) {
    final props = (feature['properties'] as Map<String, dynamic>?) ?? const {};
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coords = (geometry?['coordinates'] as List<dynamic>?) ?? const [0, 0];
    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();

    final name = (props['name'] as String?) ?? (props['street'] as String?) ?? 'Unnamed place';
    final parts = <String>[
      if (props['housenumber'] != null && props['street'] != null)
        '${props['housenumber']} ${props['street']}'
      else if (props['street'] != null)
        props['street'] as String,
      if (props['city'] != null) props['city'] as String,
      if (props['state'] != null) props['state'] as String,
      if (props['country'] != null) props['country'] as String,
    ];
    final subtitle = parts.isEmpty ? null : parts.join(', ');

    return Place(
      name: name,
      subtitle: subtitle,
      point: GeoPoint(lat, lng),
      category: _categoryFromOsmTag(props['osm_key'] as String?, props['osm_value'] as String?),
      osmId: props['osm_id']?.toString(),
    );
  }

  static PlaceCategory _categoryFromOsmTag(String? key, String? value) {
    if (key == null || value == null) return PlaceCategory.other;
    switch (key) {
      case 'amenity':
        if (value == 'fuel') return PlaceCategory.gas;
        if (value == 'parking') return PlaceCategory.parking;
        if (value == 'restaurant' || value == 'cafe' || value == 'fast_food') {
          return PlaceCategory.food;
        }
        if (value == 'drinking_water') return PlaceCategory.water;
        return PlaceCategory.business;
      case 'tourism':
        if (value == 'hotel' || value == 'motel' || value == 'guest_house') {
          return PlaceCategory.lodging;
        }
        if (value == 'camp_site') return PlaceCategory.campground;
        return PlaceCategory.other;
      case 'highway':
        return PlaceCategory.trailhead;
      case 'natural':
        if (value == 'peak') return PlaceCategory.summit;
        return PlaceCategory.other;
      case 'shop':
        return PlaceCategory.business;
      case 'building':
      case 'place':
        return PlaceCategory.address;
      default:
        return PlaceCategory.other;
    }
  }
}
