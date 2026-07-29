import 'dart:math' as math;

/// A longitude/latitude pair, in degrees.
///
/// The TypeScript app used a bare `[lon, lat]` tuple. Naming the fields here
/// removes a whole class of ordering bugs — `[lat, lon]` vs `[lon, lat]`
/// mix-ups were a recurring hazard in the original, since GeoJSON, Overpass
/// and Cesium each use a different convention.
final class LngLat {
  const LngLat(this.lon, this.lat);

  final double lon;
  final double lat;

  /// Parse a GeoJSON-order `[lon, lat]` pair.
  factory LngLat.fromGeoJson(List<num> pair) =>
      LngLat(pair[0].toDouble(), pair[1].toDouble());

  /// Emit a GeoJSON-order `[lon, lat]` pair.
  List<double> toGeoJson() => [lon, lat];

  bool get isFinite => lon.isFinite && lat.isFinite;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LngLat && other.lon == lon && other.lat == lat);

  @override
  int get hashCode => Object.hash(lon, lat);

  @override
  String toString() =>
      'LngLat(${lon.toStringAsFixed(6)}, ${lat.toStringAsFixed(6)})';
}

/// An axis-aligned geographic bounding box.
final class LatLngBounds {
  const LatLngBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// The smallest box containing every point. Returns null for an empty list.
  static LatLngBounds? containing(Iterable<LngLat> points) {
    var s = double.infinity;
    var w = double.infinity;
    var n = double.negativeInfinity;
    var e = double.negativeInfinity;
    var any = false;
    for (final p in points) {
      if (!p.isFinite) continue;
      any = true;
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lon);
      e = math.max(e, p.lon);
    }
    if (!any) return null;
    return LatLngBounds(south: s, west: w, north: n, east: e);
  }

  double get latSpan => north - south;
  double get lonSpan => east - west;

  LngLat get center => LngLat((west + east) / 2, (south + north) / 2);

  bool contains(LngLat p) =>
      p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  @override
  String toString() => 'LatLngBounds(s: $south, w: $west, n: $north, e: $east)';
}
