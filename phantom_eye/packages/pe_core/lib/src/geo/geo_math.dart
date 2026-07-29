import 'dart:math' as math;

import 'lng_lat.dart';

/// Mean Earth radius (metres) — matches the value used by the legacy
/// `haversine` in `src/routing.ts`.
const double kEarthRadiusMeters = 6371000;

/// Metres per degree of latitude, used by the local equirectangular
/// approximations below. Matches `METERS_PER_DEG_LAT` in the legacy
/// `src/streetlabels.ts`.
const double kMetersPerDegreeLat = 111320;

double _toRad(double deg) => deg * math.pi / 180;

double _toDeg(double rad) => rad * 180 / math.pi;

/// Great-circle distance in metres between two points.
///
/// Ported verbatim from `haversine` in `src/routing.ts:168`.
double haversine(LngLat a, LngLat b) {
  final dLat = _toRad(b.lat - a.lat);
  final dLon = _toRad(b.lon - a.lon);
  final lat1 = _toRad(a.lat);
  final lat2 = _toRad(b.lat);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  return 2 * kEarthRadiusMeters * math.asin(math.sqrt(h.toDouble()));
}

/// Compass bearing from `a` to `b`.
///
/// Ported verbatim from `bearingDeg` in `src/geo.ts:4`. Note this returns the
/// raw `atan2` result in **-180..180**, not a normalised 0..360 compass
/// bearing — the legacy callers depend on that range, so it is preserved
/// exactly. Use [normalizeBearing] where a 0..360 value is wanted.
double bearingDeg(LngLat a, LngLat b) {
  final lat1 = _toRad(a.lat);
  final lat2 = _toRad(b.lat);
  final dLon = _toRad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return _toDeg(math.atan2(y, x));
}

/// Wrap a bearing into 0..360.
double normalizeBearing(double deg) {
  final d = deg % 360;
  return d < 0 ? d + 360 : d;
}

/// Wrap an angle difference into -180..180.
///
/// Ported from `normalizeAngleDeg` in the legacy `src/streetlabels.ts`.
double normalizeAngleDelta(double deg) {
  var d = deg % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// The point `distanceMeters` away from `origin` along `bearing`, using the
/// standard spherical destination formula.
///
/// Ported from `destinationPoint` in the legacy `src/streetlabels.ts`.
LngLat destinationPoint(
  LngLat origin,
  double bearingDegrees,
  double distanceMeters,
) {
  final brng = _toRad(bearingDegrees);
  final lat1 = _toRad(origin.lat);
  final lon1 = _toRad(origin.lon);
  final angDist = distanceMeters / kEarthRadiusMeters;
  final lat2 = math.asin(
    math.sin(lat1) * math.cos(angDist) +
        math.cos(lat1) * math.sin(angDist) * math.cos(brng),
  );
  final lon2 =
      lon1 +
      math.atan2(
        math.sin(brng) * math.sin(angDist) * math.cos(lat1),
        math.cos(angDist) - math.sin(lat1) * math.sin(lat2),
      );
  return LngLat(_toDeg(lon2), _toDeg(lat2));
}

/// Planar distance in metres using a local equirectangular approximation.
///
/// Cheaper than [haversine] and accurate over the short spans between route
/// vertices. Ported from `metersBetween` in the legacy `src/streetlabels.ts`,
/// including its `cos(lat)` floor of 0.2 which keeps the approximation from
/// collapsing near the poles.
double metersBetweenApprox(LngLat a, LngLat b) {
  final cosLat = math.max(math.cos(_toRad((a.lat + b.lat) / 2)), 0.2);
  final dx = (b.lon - a.lon) * cosLat * kMetersPerDegreeLat;
  final dy = (b.lat - a.lat) * kMetersPerDegreeLat;
  return math.sqrt(dx * dx + dy * dy);
}

/// Cumulative along-path distance (metres) for each vertex; always starts at 0
/// and has the same length as `points`.
///
/// Ported from `cumulative` in `src/navigation.ts:401`.
List<double> cumulativeDistances(List<LngLat> points) {
  final cum = <double>[0];
  for (var i = 1; i < points.length; i++) {
    cum.add(cum[i - 1] + haversine(points[i - 1], points[i]));
  }
  return cum;
}

/// Result of projecting a point onto a single segment.
typedef SegmentProjection = ({double t, double distanceMeters});

/// Project `p` onto segment `a`–`b`, returning the clamped parameter `t` in
/// 0..1 and the perpendicular distance in metres.
///
/// Uses the same local equirectangular trick as the legacy `projectOnRoute` /
/// `projectOntoDrivePath`: scale longitude by `cos(lat)` so the maths can be
/// done in a flat plane, then convert the squared result back to metres via
/// [kMetersPerDegreeLat]. Written with inline scalars (no tuple allocation)
/// because this runs once per route segment on every GPS fix.
SegmentProjection projectPointOnSegment(LngLat p, LngLat a, LngLat b) {
  final kx = math.cos(_toRad(p.lat));
  final ax = (a.lon - p.lon) * kx;
  final ay = a.lat - p.lat;
  final bx = (b.lon - p.lon) * kx;
  final by = b.lat - p.lat;
  final abx = bx - ax;
  final aby = by - ay;
  var len2 = abx * abx + aby * aby;
  if (len2 == 0) len2 = 1e-12;
  var t = -(ax * abx + ay * aby) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + abx * t;
  final cy = ay + aby * t;
  final d = math.sqrt(cx * cx + cy * cy) * kMetersPerDegreeLat;
  return (t: t, distanceMeters: d);
}

/// Linearly interpolate between two points.
LngLat lerpLngLat(LngLat a, LngLat b, double t) =>
    LngLat(a.lon + (b.lon - a.lon) * t, a.lat + (b.lat - a.lat) * t);
