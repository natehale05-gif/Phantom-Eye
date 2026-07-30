import 'package:pe_core/pe_core.dart';

/// Parsers for Photon (photon.komoot.io), the keyless OSM geocoder.
///
/// Photon answers GeoJSON: a `features` array whose `properties` carry the
/// address components. The three line builders below decide what every search
/// row reads like, so they are ported field-for-field from `src/geocode.ts`
/// rather than re-derived.

/// The primary label for a result.
///
/// Ported from `displayName` in `src/geocode.ts:89`. A POI uses its name; a
/// plain address uses `housenumber street` (or just the street when there is
/// no number); otherwise it falls back through city → state → country. An
/// empty result here means the feature is unusable and is dropped.
String photonDisplayName(Map<String, dynamic> p) {
  final name = _str(p['name']);
  if (name != null) return name;
  final street = _str(p['street']);
  if (street != null) {
    final houseNumber = _str(p['housenumber']);
    return houseNumber != null ? '$houseNumber $street' : street;
  }
  return _str(p['city']) ?? _str(p['state']) ?? _str(p['country']) ?? '';
}

/// The full postal-style address.
///
/// Ported from `addressLine` in `src/geocode.ts:95`. Note the street part
/// needs *both* a housenumber and a street to be combined, but falls back to
/// the bare street when the number is missing — so `Main St` is still shown.
String photonAddressLine(Map<String, dynamic> p) {
  final housenumber = _str(p['housenumber']);
  final street = _str(p['street']);
  final streetLine = (housenumber != null && street != null)
      ? '$housenumber $street'
      : street;
  final cityLine = [
    _str(p['city']) ?? _str(p['locality']),
    _str(p['state']),
    _str(p['postcode']),
  ].whereType<String>().join(', ');
  return [
    streetLine,
    cityLine.isEmpty ? null : cityLine,
  ].whereType<String>().join(', ');
}

/// The secondary line shown under [photonDisplayName].
///
/// Ported from `detailLine` in `src/geocode.ts:101`. Every part is suppressed
/// when it merely repeats the name — otherwise searching "Portland" would
/// render a row reading "Portland / Portland, Oregon". Country appears only
/// when nothing else survived that filter.
String photonDetailLine(Map<String, dynamic> p, String name) {
  final parts = <String>[];

  final housenumber = _str(p['housenumber']);
  final street = _str(p['street']);
  final streetLine = (housenumber != null && street != null)
      ? '$housenumber $street'
      : street;
  if (streetLine != null && streetLine != name) parts.add(streetLine);

  final town = _str(p['city']) ?? _str(p['locality']) ?? _str(p['county']);
  if (town != null && town != name) parts.add(town);

  final state = _str(p['state']);
  if (state != null && state != name && state != town) parts.add(state);

  if (parts.isEmpty) {
    final country = _str(p['country']);
    if (country != null) parts.add(country);
  }
  return parts.join(', ');
}

/// Parse a Photon forward-search response into places.
///
/// Ported from `searchPlaces` in `src/geocode.ts:51`, including its dedupe:
/// results are keyed on `name@lon,lat` with the coordinates rounded to 4
/// decimal places (~11 m), which collapses the duplicate rows Photon returns
/// when the same POI exists as both a node and a way. The rounding is
/// deliberately coarse — exact coordinate equality would never fire.
List<Place> parsePhotonSearch(Map<String, dynamic> body) {
  final features = body['features'];
  if (features is! List) return const [];

  final out = <Place>[];
  final seen = <String>{};
  for (final feature in features) {
    if (feature is! Map<String, dynamic>) continue;
    final geometry = feature['geometry'];
    if (geometry is! Map<String, dynamic>) continue;
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) continue;
    final lon = coords[0];
    final lat = coords[1];
    if (lon is! num || lat is! num) continue;

    final props = feature['properties'];
    final p = props is Map<String, dynamic> ? props : const <String, dynamic>{};
    final name = photonDisplayName(p);
    if (name.isEmpty) continue;

    final key = '$name@${lon.toStringAsFixed(4)},${lat.toStringAsFixed(4)}';
    if (!seen.add(key)) continue;

    final address = photonAddressLine(p);
    out.add(
      Place(
        name: name,
        detail: photonDetailLine(p, name),
        position: LngLat(lon.toDouble(), lat.toDouble()),
        category: _str(p['osm_value']) ?? _str(p['osm_key']) ?? '',
        osmType: OsmType.parse(p['osm_type']),
        osmId: p['osm_id'] is num ? (p['osm_id'] as num).toInt() : null,
        details: PlaceDetails(address: address.isEmpty ? null : address),
      ),
    );
  }
  return out;
}

/// Place types Photon's reverse endpoint reports that name a settlement.
///
/// Ported from `PLACE_TYPES` in `src/weather.ts:256`.
const Set<String> kPhotonPlaceTypes = {
  'city',
  'town',
  'village',
  'hamlet',
  'municipality',
  'locality',
  'suburb',
  'neighbourhood',
};

/// Pull a friendly settlement name out of a Photon reverse response.
///
/// Ported from `reverseName` in `src/weather.ts:255`. The preference order is
/// load-bearing: `city` first, then `name` but **only when the feature's own
/// type says it is a settlement** — otherwise reverse-geocoding a point next
/// to a restaurant would report the restaurant as your location. Only after
/// that does a bare `name` count, then county, then state.
///
/// Returns null when the response names nothing usable, so the caller can
/// fall through to the next provider.
String? parsePhotonReverseName(Map<String, dynamic> body) {
  final features = body['features'];
  if (features is! List || features.isEmpty) return null;
  final first = features.first;
  if (first is! Map<String, dynamic>) return null;
  final props = first['properties'];
  if (props is! Map<String, dynamic>) return null;

  final type = _str(props['type']);
  final name = _str(props['name']);
  return _str(props['city']) ??
      (type != null && kPhotonPlaceTypes.contains(type) ? name : null) ??
      name ??
      _str(props['county']) ??
      _str(props['state']);
}

/// Read a non-empty string, treating empty and non-strings alike as absent.
///
/// The TypeScript used `??` against `undefined` but also relied on `''` being
/// falsy in the `if (p.name)` checks. Collapsing both to null here keeps the
/// two behaviours identical without sprinkling `isEmpty` at each use.
String? _str(Object? v) {
  if (v is String && v.isNotEmpty) return v;
  return null;
}
