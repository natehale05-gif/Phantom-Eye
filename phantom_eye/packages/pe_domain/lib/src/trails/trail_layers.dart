import 'dart:math' as math;

import 'package:pe_core/pe_core.dart';

/// Trail overlays for Offroad (4x4/OHV), Hiking and Bike — the OnX-style
/// layers, sourced from OpenStreetMap via Overpass.
///
/// Ported from `src/trails.ts`. Only the pure half lives here: which query to
/// send, how to grade what comes back, how big an area to ask for, and how to
/// key the cache. Drawing the polylines onto the map surface belongs to the
/// map package.

/// The three trail layers.
///
/// Ported from `TrailLayerId` in `src/trails.ts:20`.
enum TrailLayerId {
  offroad('offroad'),
  hiking('hiking'),
  bike('bike');

  const TrailLayerId(this.id);

  /// Stable string id, used in storage keys and query selection.
  final String id;

  static TrailLayerId? parse(String value) {
    for (final l in values) {
      if (l.id == value) return l;
    }
    return null;
  }
}

/// How hard a trail is, and the colour it draws in.
///
/// Ported from `DIFFICULTY` in `src/trails.ts:28`. Green/blue/black/red is
/// the ski-run convention every trail app uses, so it needs no legend.
enum TrailDifficulty {
  easy('#34C759'),
  intermediate('#0A84FF'),
  advanced('#111111'),
  expert('#FF3B30'),
  unrated('#8E8E93');

  const TrailDifficulty(this.colorHex);

  final String colorHex;
}

/// How the load of a layer is progressing, for the status toast.
///
/// Ported from `TrailStatus` in `src/trails.ts:21`.
enum TrailStatus { loading, done, empty, error }

/// Above this camera altitude (metres) trails are not fetched at all.
///
/// Ported from `MAX_ALTITUDE` in `src/trails.ts:24`. From high up the query
/// area covers a whole region and Overpass either times out or returns more
/// than can be drawn, so the layer simply reports empty.
const double kTrailMaxAltitudeMeters = 22000;

/// Largest half-span (degrees of latitude) of a trail query area.
///
/// Ported from `MAX_SPAN_DEG / 2` in `src/trails.ts:25`.
///
/// **This clamp is unreachable through the normal path**, in the original as
/// much as here: the half-span is `altitude / 111000 * 0.9`, and the altitude
/// cutoff of [kTrailMaxAltitudeMeters] caps it at 0.178° — reaching 0.25°
/// would need a camera about 30.8 km up, which is already refused. It is kept
/// as a backstop in case the altitude cutoff is raised.
const double kTrailMaxHalfSpanDegrees = 0.25;

/// Smallest half-span, so a very low camera still queries a usable area.
const double kTrailMinHalfSpanDegrees = 0.02;

/// Ways requested and retained per layer.
///
/// Ported from `MAX_WAYS` in `src/trails.ts:26`.
const int kTrailMaxWays = 400;

/// Vertices retained per way.
///
/// Ported from `MAX_PTS_PER_WAY` in `src/trails.ts:51`. Trails come back with
/// full survey detail — hundreds of points for a single switchback — which
/// costs far more to drape and draw than it adds visually.
const int kTrailMaxPointsPerWay = 48;

/// View tiles cached per layer.
///
/// Ported from `MAX_CACHE_TILES` in `src/trails.ts:56`. Bounded so a long
/// panning session across many distinct view tiles cannot grow it forever.
const int kTrailCacheTiles = 60;

/// Server-side timeout baked into the query, in seconds.
const int kTrailOverpassTimeout = 25;

/// One trail, ready to draw.
final class TrailWay {
  const TrailWay({required this.points, required this.difficulty});

  final List<LngLat> points;
  final TrailDifficulty difficulty;

  @override
  String toString() => 'TrailWay(${points.length} pts, ${difficulty.name})';
}

/// The Overpass clause list for each layer.
///
/// Ported verbatim from `QUERY` in `src/trails.ts:304`. Each entry is one
/// union member; [buildTrailQuery] appends the bbox and the separators.
const Map<TrailLayerId, List<String>> kTrailClauses = {
  TrailLayerId.hiking: [
    'way["highway"="path"]',
    'way["highway"="footway"]["footway"!="sidewalk"]',
    'way["highway"="bridleway"]',
    'way["highway"="steps"]',
    'way["sac_scale"]',
  ],
  TrailLayerId.bike: [
    // Dedicated cycling infrastructure.
    'way["highway"="cycleway"]',
    'way["bicycle"="designated"]',
    'way["cycleway"~"lane|track|shared_lane|opposite_lane"]',
    // Off-road / mountain-bike trails.
    'way["mtb:scale"]',
    'way["mtb:scale:imba"]',
    'way["highway"~"path|track"]["bicycle"~"designated|yes"]',
    // Signed cycle routes (numbered/named networks) arrive as relations.
    'relation["route"="bicycle"]',
    'relation["route"="mtb"]',
  ],
  TrailLayerId.offroad: [
    'way["highway"="track"]',
    'way["4wd_only"="yes"]',
    'way["highway"="path"]["motor_vehicle"~"designated|yes"]',
  ],
};

/// Build the Overpass QL for one layer over one area.
///
/// Ported from `fetchTrails` in `src/trails.ts:229`. `out geom` is what makes
/// this usable — unlike the nearby search, whole line geometries are needed,
/// not centroids.
///
/// Note every union member ends in `;`, **including the last one before the
/// closing paren**. Joining the clauses with `;` omits that final separator
/// and Overpass rejects the whole query with a 400, which is the kind of
/// failure that looks like a dead mirror rather than a malformed request.
String buildTrailQuery(TrailLayerId layer, LatLngBounds bounds) {
  final bbox =
      '(${bounds.south},${bounds.west},${bounds.north},${bounds.east})';
  final clauses = StringBuffer();
  for (final clause in kTrailClauses[layer]!) {
    clauses.write('$clause$bbox;');
  }
  return '[out:json][timeout:$kTrailOverpassTimeout];'
      '($clauses);'
      'out geom $kTrailMaxWays;';
}

/// Grade a trail from its OSM tags.
///
/// Ported from `GRADERS` in `src/trails.ts:343`.
///
/// These tables are transcribed rather than generated: `GRADERS` is
/// module-private in `trails.ts` and only reachable through a `Cesium.Viewer`,
/// so unlike the category and maneuver tables there is no honest way to
/// execute the original headlessly and diff against it. The tests below are
/// table-driven against the source as written.
TrailDifficulty gradeTrail(TrailLayerId layer, Map<String, String> tags) =>
    switch (layer) {
      TrailLayerId.hiking => _gradeHiking(tags),
      TrailLayerId.bike => _gradeBike(tags),
      TrailLayerId.offroad => _gradeOffroad(tags),
    };

TrailDifficulty _gradeHiking(Map<String, String> tags) {
  switch (tags['sac_scale']) {
    case 'hiking':
      return TrailDifficulty.easy;
    case 'mountain_hiking':
      return TrailDifficulty.intermediate;
    case 'demanding_mountain_hiking':
      return TrailDifficulty.advanced;
    case 'alpine_hiking':
    case 'demanding_alpine_hiking':
    case 'difficult_alpine_hiking':
      return TrailDifficulty.expert;
  }
  // Steps and very poor visibility read as harder even with no SAC scale.
  if (tags['highway'] == 'steps') return TrailDifficulty.intermediate;
  final visibility = tags['trail_visibility'];
  if (visibility == 'bad' || visibility == 'horrible' || visibility == 'no') {
    return TrailDifficulty.advanced;
  }
  return TrailDifficulty.easy;
}

TrailDifficulty _gradeBike(Map<String, String> tags) {
  final imba = leadingInt(tags['mtb:scale:imba']);
  if (imba != null) {
    if (imba <= 1) return TrailDifficulty.easy;
    if (imba == 2) return TrailDifficulty.intermediate;
    if (imba == 3) return TrailDifficulty.advanced;
    return TrailDifficulty.expert;
  }
  final scale = leadingInt(tags['mtb:scale']);
  if (scale != null) {
    if (scale <= 1) return TrailDifficulty.easy;
    if (scale <= 3) return TrailDifficulty.intermediate;
    if (scale == 4) return TrailDifficulty.advanced;
    return TrailDifficulty.expert;
  }
  // A regular cycleway or signed route has no off-road difficulty at all.
  return TrailDifficulty.easy;
}

TrailDifficulty _gradeOffroad(Map<String, String> tags) {
  switch (tags['tracktype']) {
    case 'grade1':
      return TrailDifficulty.easy;
    case 'grade2':
      return TrailDifficulty.intermediate;
    case 'grade3':
      return TrailDifficulty.advanced;
    case 'grade4':
    case 'grade5':
      return TrailDifficulty.expert;
  }
  switch (tags['smoothness']) {
    case 'excellent':
    case 'good':
      return TrailDifficulty.easy;
    case 'intermediate':
      return TrailDifficulty.intermediate;
    case 'bad':
      return TrailDifficulty.advanced;
    case 'very_bad':
    case 'horrible':
    case 'very_horrible':
    case 'impassable':
      return TrailDifficulty.expert;
  }
  if (tags['4wd_only'] == 'yes') return TrailDifficulty.advanced;
  return TrailDifficulty.easy;
}

/// Read the leading integer of a value like `3` or `3+` or `S2`.
///
/// Ported from `leadingInt` in `src/trails.ts`. The MTB scales are tagged
/// inconsistently in the wild — `mtb:scale=3+` is common — so a strict parse
/// would silently drop the grading for a large share of real trails.
int? leadingInt(String? value) {
  if (value == null) return null;
  final match = RegExp(r'\d+').firstMatch(value);
  if (match == null) return null;
  return int.tryParse(match.group(0)!);
}

/// Turn an Overpass `out geom` response into drawable ways.
///
/// Ported from `fetchTrails` in `src/trails.ts:243`. Two element shapes are
/// handled:
///
///  * a **way** carries its own `geometry`;
///  * a **relation** (a signed cycle or MTB route) carries member ways, each
///    drawn with the **relation's** tags rather than its own, so the whole
///    numbered route shares one difficulty colour instead of flickering
///    between grades along its length.
List<TrailWay> parseTrailWays(
  Iterable<Map<String, dynamic>> elements,
  TrailLayerId layer, {
  int maxWays = kTrailMaxWays,
}) {
  final out = <TrailWay>[];

  void add(Object? geometry, Map<String, String> tags) {
    if (out.length >= maxWays) return;
    final points = _geometryPoints(geometry);
    // A single-point "line" is not drawable.
    if (points.length < 2) return;
    out.add(
      TrailWay(
        points: downsampleTrailWay(points),
        difficulty: gradeTrail(layer, tags),
      ),
    );
  }

  for (final element in elements) {
    if (out.length >= maxWays) break;
    final tags = _stringTags(element['tags']);
    final type = element['type'];

    if (type == 'way') {
      add(element['geometry'], tags);
    } else if (type == 'relation') {
      final members = element['members'];
      if (members is! List) continue;
      for (final member in members) {
        if (out.length >= maxWays) break;
        if (member is! Map<String, dynamic>) continue;
        if (member['type'] != 'way') continue;
        add(member['geometry'], tags);
      }
    }
  }
  return out;
}

List<LngLat> _geometryPoints(Object? geometry) {
  if (geometry is! List) return const [];
  final out = <LngLat>[];
  for (final point in geometry) {
    if (point is! Map) continue;
    final lat = point['lat'];
    final lon = point['lon'];
    if (lat is num && lon is num) {
      out.add(LngLat(lon.toDouble(), lat.toDouble()));
    }
  }
  return out;
}

Map<String, String> _stringTags(Object? raw) => {
  if (raw is Map)
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
};

/// Thin a way down to at most [kTrailMaxPointsPerWay] vertices.
///
/// Ported from `downsampleCoords` in `src/trails.ts:58`. Points are taken by
/// striding rather than truncating, so the shape survives, and **the final
/// vertex is always kept** — dropping it leaves the drawn line stopping short
/// of where the trail actually ends, which is worse than a slightly coarser
/// curve.
List<LngLat> downsampleTrailWay(
  List<LngLat> points, {
  int maxPoints = kTrailMaxPointsPerWay,
}) {
  if (points.length <= maxPoints) return points;
  final stride = (points.length / maxPoints).ceil();
  final out = <LngLat>[];
  for (var i = 0; i < points.length; i += stride) {
    out.add(points[i]);
  }
  final last = points.last;
  if (out.isEmpty || out.last != last) out.add(last);
  return out;
}

/// The ground area to query for a camera at [centre] and [altitudeMeters].
///
/// Ported from `viewArea` in `src/trails.ts:158`. Returns null above
/// [kTrailMaxAltitudeMeters], which is how "too zoomed out" is reported.
///
/// The area is centred on the **camera's own ground position**, not the
/// screen-centre pick: in a tilted chase view the screen centre shoots off
/// toward the horizon, and `computeViewRectangle` returns null or a
/// whole-globe rectangle, either of which silently prevented trails from
/// loading at all.
///
/// The longitude half-span is divided by `cos(lat)`. That is deliberate and
/// correct — it keeps the queried box roughly **square in ground distance**
/// rather than in degrees, so the same number of trails comes back in Alaska
/// as in Oregon. It looks like a missing clamp and is not one. The cosine is
/// floored at 0.2 so the division cannot explode near the poles.
LatLngBounds? trailViewArea(LngLat centre, double altitudeMeters) {
  if (!centre.isFinite || !altitudeMeters.isFinite) return null;
  if (altitudeMeters > kTrailMaxAltitudeMeters) return null;

  final half = (altitudeMeters / 111000 * 0.9).clamp(
    kTrailMinHalfSpanDegrees,
    kTrailMaxHalfSpanDegrees,
  );
  final cosLat = math.max(math.cos(centre.lat * math.pi / 180), 0.2);
  final halfLon = half / cosLat;

  return LatLngBounds(
    south: centre.lat - half,
    north: centre.lat + half,
    west: centre.lon - halfLon,
    east: centre.lon + halfLon,
  );
}

/// The cache key for a query area.
///
/// Ported from the `lastKey` computation in `src/trails.ts:184`. Two decimal
/// places (~1 km) is what makes panning cheap: nudging the camera a block
/// resolves to the same key and reuses the previous result instead of hitting
/// Overpass again.
String trailCacheKey(LatLngBounds bounds) =>
    '${bounds.south.toStringAsFixed(2)},${bounds.west.toStringAsFixed(2)},'
    '${bounds.north.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)}';
