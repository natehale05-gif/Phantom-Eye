import 'dart:math' as math;

/// Lightweight, plugin-independent lat/lng value type.
///
/// Kept separate from `maplibre_gl`'s `LatLng` so that models, services,
/// routing, GPX, and Meshtastic code never need to import the map plugin —
/// only the map-shell widgets do the `GeoPoint <-> LatLng` conversion at the
/// boundary.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'lat': latitude, 'lng': longitude};

  @override
  String toString() =>
      'GeoPoint(${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)})';

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// A point with elevation, used for routes/tracks where altitude matters
/// (elevation profile, gain/loss for the offroad builder & track recorder).
class ElevationPoint {
  const ElevationPoint(this.point, this.elevationMeters, {this.distanceFromStartMeters = 0});

  final GeoPoint point;
  final double elevationMeters;
  final double distanceFromStartMeters;
}

/// A timestamped GPS fix, used for recorded tracks and the nav simulator.
class TimedPoint {
  const TimedPoint(this.point, this.timestamp, {this.speedMps, this.headingDeg, this.elevationMeters});

  final GeoPoint point;
  final DateTime timestamp;
  final double? speedMps;
  final double? headingDeg;
  final double? elevationMeters;
}

/// Geodesic helpers ported from the prototype's framework-agnostic JS math
/// (haversine distance, initial bearing, destination point) — these are
/// standard spherical-earth formulas, verified against the usual references
/// rather than any handoff doc (none existed for this build).
abstract final class GeoMath {
  static const double earthRadiusMeters = 6371000.0;

  static double _degToRad(double deg) => deg * math.pi / 180.0;
  static double _radToDeg(double rad) => rad * 180.0 / math.pi;

  /// Great-circle distance between two points, in meters.
  static double distanceMeters(GeoPoint a, GeoPoint b) {
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final dLat = lat2 - lat1;
    final dLng = _degToRad(b.longitude - a.longitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final h = sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLng * sinDLng;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadiusMeters * c;
  }

  /// Initial compass bearing (degrees, 0-360, 0 = north) from [a] to [b].
  static double bearingDegrees(GeoPoint a, GeoPoint b) {
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final theta = math.atan2(y, x);
    return (_radToDeg(theta) + 360) % 360;
  }

  /// Smallest signed angular difference between two headings, in degrees
  /// (-180, 180]. Used to decide turn direction / lane guidance.
  static double angleDiffDegrees(double from, double to) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  /// Point at [distanceMeters] along [bearingDeg] from [origin].
  static GeoPoint destinationPoint(GeoPoint origin, double bearingDeg, double distanceMeters) {
    final delta = distanceMeters / earthRadiusMeters;
    final theta = _degToRad(bearingDeg);
    final lat1 = _degToRad(origin.latitude);
    final lng1 = _degToRad(origin.longitude);

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(delta) + math.cos(lat1) * math.sin(delta) * math.cos(theta),
    );
    final lng2 = lng1 +
        math.atan2(
          math.sin(theta) * math.sin(delta) * math.cos(lat1),
          math.cos(delta) - math.sin(lat1) * math.sin(lat2),
        );

    return GeoPoint(_radToDeg(lat2), (_radToDeg(lng2) + 540) % 360 - 180);
  }

  /// Total path length of a polyline, in meters.
  static double pathLengthMeters(List<GeoPoint> path) {
    double total = 0;
    for (var i = 0; i < path.length - 1; i++) {
      total += distanceMeters(path[i], path[i + 1]);
    }
    return total;
  }

  /// Finds the closest point on segment [a]-[b] to [p], returning both the
  /// projected point and the fractional distance (0..1) along the segment.
  /// Used for off-route detection & snapping the nav puck to the route line.
  static ({GeoPoint point, double t, double distanceMeters}) closestPointOnSegment(
    GeoPoint p,
    GeoPoint a,
    GeoPoint b,
  ) {
    // Equirectangular approximation is plenty accurate at route-segment
    // scale (tens to low-hundreds of meters) and much cheaper than exact
    // geodesic projection.
    final latRad = _degToRad((a.latitude + b.latitude) / 2);
    final xScale = math.cos(latRad);

    final ax = a.longitude * xScale;
    final ay = a.latitude;
    final bx = b.longitude * xScale;
    final by = b.latitude;
    final px = p.longitude * xScale;
    final py = p.latitude;

    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;

    double t;
    if (lenSq == 0) {
      t = 0;
    } else {
      t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
      t = t.clamp(0.0, 1.0);
    }

    final projLng = (ax + t * dx) / xScale;
    final projLat = ay + t * dy;
    final projected = GeoPoint(projLat, projLng);
    return (point: projected, t: t, distanceMeters: distanceMeters(p, projected));
  }
}
