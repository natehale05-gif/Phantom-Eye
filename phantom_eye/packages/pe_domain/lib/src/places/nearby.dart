import 'package:pe_core/pe_core.dart';

import 'categories.dart';

/// Search radius for a category chip, in metres.
///
/// Ported from `RADIUS_M` in `src/nearby.ts:14`.
const int kNearbyRadiusMeters = 3000;

/// How many results the list shows.
///
/// Ported from `MAX_RESULTS` in `src/nearby.ts:15`.
const int kNearbyMaxResults = 18;

/// Overpass is asked for three times [kNearbyMaxResults].
///
/// The overshoot exists because a good share of elements come back unnamed
/// or duplicated between the node and way copies of the same POI, and those
/// are dropped before the list is capped.
const int kNearbyOverpassLimit = kNearbyMaxResults * 3;

/// Server-side timeout baked into the Overpass query, in seconds.
const int kNearbyOverpassTimeout = 20;

/// Build the Overpass QL for a category chip search around a point.
///
/// Ported from `searchNearby` in `src/nearby.ts:26`. Each tag pair becomes a
/// `node` clause and a `way` clause; **relations are deliberately not
/// queried**, because the handful of POIs mapped as relations are not worth
/// the cost of the extra recursion on a public mirror.
///
/// `out center` is what makes way results usable — a way has no coordinate of
/// its own, so Overpass is asked to emit the centroid of its geometry.
String buildNearbyQuery(Category category, LngLat near) {
  final around = 'around:$kNearbyRadiusMeters,${near.lat},${near.lon}';
  final clauses = StringBuffer();
  for (final tag in category.osmTags) {
    clauses.write('node["${tag.key}"="${tag.value}"]($around);');
    clauses.write('way["${tag.key}"="${tag.value}"]($around);');
  }
  return '[out:json][timeout:$kNearbyOverpassTimeout];'
      '($clauses);'
      'out center $kNearbyOverpassLimit;';
}

/// Build the Overpass QL that fetches full tags for one element.
///
/// Ported from `fetchPlaceDetails` in `src/nearby.ts:103`, used to enrich a
/// place card whose result arrived from the text geocoder without contact
/// tags.
String buildPlaceDetailsQuery(OsmType type, int id) =>
    '[out:json][timeout:15];${type.osmName}($id);out tags;';

/// Turn one Overpass element into a [Place], or null if it is unusable.
///
/// Elements without a `name` tag are dropped — an unnamed node is not
/// something a user can be told to drive to. A way carries its coordinate in
/// `center` rather than `lat`/`lon`, which is why both shapes are read.
Place? placeFromOverpassElement(
  Map<String, dynamic> element, {
  required Category category,
}) {
  final rawTags = element['tags'];
  final tags = <String, String>{
    if (rawTags is Map)
      for (final entry in rawTags.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
  };

  final name = tags['name'];
  if (name == null || name.isEmpty) return null;

  final position = _positionOf(element);
  if (position == null) return null;

  final id = element['id'];
  return Place(
    name: name,
    detail: overpassDetailLine(tags),
    position: position,
    category: category.label,
    categoryId: category.id,
    osmType: OsmType.parse(element['type']),
    osmId: id is num ? id.toInt() : null,
    details: overpassDetails(tags),
  );
}

LngLat? _positionOf(Map<String, dynamic> element) {
  final center = element['center'];
  if (center is Map) {
    final lat = center['lat'];
    final lon = center['lon'];
    if (lat is num && lon is num) return LngLat(lon.toDouble(), lat.toDouble());
  }
  final lat = element['lat'];
  final lon = element['lon'];
  if (lat is num && lon is num) return LngLat(lon.toDouble(), lat.toDouble());
  return null;
}

/// The secondary line under a nearby result.
///
/// Ported from `detailLine` in `src/nearby.ts:72`: street, city and cuisine
/// are collected, cuisine has its underscores turned into spaces, and at most
/// the first two survive so the row cannot overflow.
String overpassDetailLine(Map<String, String> tags) {
  final house = tags['addr:housenumber'];
  final street = tags['addr:street'];
  final streetLine = (house != null && street != null)
      ? '$house $street'
      : street;
  final bits = <String>[
    if (streetLine != null && streetLine.isNotEmpty) streetLine,
    if (tags['addr:city'] case final city? when city.isNotEmpty) city,
    if (tags['cuisine'] case final cuisine? when cuisine.isNotEmpty)
      cuisine.replaceAll('_', ' '),
  ];
  return bits.take(2).join(' · ');
}

/// Contact and address details from OSM tags.
///
/// Ported from `tagsToDetails` in `src/nearby.ts:82`. The `contact:` prefixed
/// forms are the older tagging scheme and are still common, so both are read.
PlaceDetails overpassDetails(Map<String, String> tags) {
  final house = tags['addr:housenumber'];
  final street = tags['addr:street'];
  final streetLine = (house != null && street != null)
      ? '$house $street'
      : street;
  final address = [
    streetLine,
    tags['addr:city'],
    tags['addr:state'],
    tags['addr:postcode'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  return PlaceDetails(
    phone: tags['phone'] ?? tags['contact:phone'],
    website: tags['website'] ?? tags['contact:website'] ?? tags['url'],
    openingHours: tags['opening_hours'],
    address: address.isEmpty ? null : address,
  );
}

/// Parse, rank and cap a nearby response.
///
/// The ordering here is the fix for a real defect in `src/nearby.ts:46`,
/// which deduped on the **lowercased name** while streaming elements in, and
/// only sorted by distance afterwards. Two consequences, both visible:
///
///  * every branch of a chain collapsed to one row — search "coffee" in a
///    city and you saw a single Starbucks, not the four around you;
///  * the survivor was whichever one Overpass happened to emit first, which
///    is element-id order, so the one row you *did* get was routinely not the
///    nearest. Sorting afterwards could not undo that, because the nearer
///    branches had already been discarded.
///
/// Here the list is sorted by distance **first**, then deduped in two passes:
/// by OSM identity, and by same-name-within-[kNearbyDuplicateMeters]. The
/// second pass is what still collapses the one duplicate the original was
/// right to collapse — a POI mapped as both a node and the building way
/// around it arrives as two elements with two different ids at the same spot —
/// while leaving two branches a block apart as the two results they are.
/// Because the sort runs first, the copy that survives is the nearest.
List<Place> rankNearbyResults(
  Iterable<Map<String, dynamic>> elements, {
  required Category category,
  required LngLat near,
  int maxResults = kNearbyMaxResults,
}) {
  final scored = <({Place place, double distance})>[];
  for (final element in elements) {
    final place = placeFromOverpassElement(element, category: category);
    if (place == null) continue;
    scored.add((place: place, distance: haversine(near, place.position)));
  }

  scored.sort((a, b) => a.distance.compareTo(b.distance));

  final out = <Place>[];
  final seenIds = <String>{};
  for (final entry in scored) {
    final place = entry.place;
    final id = place.osmKey;
    if (id != null && !seenIds.add(id)) continue;
    if (_isColocatedDuplicate(place, out)) continue;
    out.add(place);
    if (out.length >= maxResults) break;
  }
  return out;
}

/// How close two same-named results must be to count as one place.
///
/// Sized to cover a POI node sitting inside its own building way, and to stay
/// well under the distance between two branches of the same chain.
const double kNearbyDuplicateMeters = 80;

bool _isColocatedDuplicate(Place candidate, List<Place> kept) {
  final name = candidate.name.toLowerCase();
  for (final other in kept) {
    if (other.name.toLowerCase() != name) continue;
    if (haversine(candidate.position, other.position) <=
        kNearbyDuplicateMeters) {
      return true;
    }
  }
  return false;
}
