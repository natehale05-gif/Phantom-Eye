import 'dart:math' as math;

import 'package:pe_core/pe_core.dart';

/// How many segments either side of the last match to search.
///
/// Ported from `PROJECT_WINDOW_SEGMENTS` in `src/navigation.ts`. A vehicle
/// moves monotonically along its route almost always, so a window around the
/// previous match reliably contains the true nearest segment; this turns an
/// O(n) rescan of a route that may hold thousands of vertices into O(1)
/// amortised work per GPS fix.
const int kProjectWindowSegments = 40;

/// Where a point sits relative to a route.
final class RouteProjection {
  const RouteProjection({
    required this.alongMeters,
    required this.bearing,
    required this.offsetMeters,
    required this.segmentIndex,
  });

  /// Distance travelled along the route to the projected point, in metres.
  final double alongMeters;

  /// Heading of the road at the matched segment, in degrees.
  final double bearing;

  /// Perpendicular distance from the route, in metres.
  final double offsetMeters;

  /// Index of the matched segment; feed back in as the next call's hint.
  final int segmentIndex;
}

/// Projects live positions onto a route, using a rolling search window.
///
/// Ported from `projectOnRoute` in `src/navigation.ts:412` together with the
/// `lastMatchedSeg` bookkeeping that lived in the `Navigator` class. Keeping
/// the hint inside this object (rather than in the caller) is what makes the
/// windowing safe: [reset] is the single place that has to be remembered, and
/// it is called from exactly one place — whenever the route changes.
final class RouteProjector {
  RouteProjector({required List<LngLat> coordinates, List<double>? cumulative})
    : _coords = coordinates,
      _cum = cumulative ?? cumulativeDistances(coordinates);

  final List<LngLat> _coords;
  final List<double> _cum;

  /// -1 means "no hint yet — do a full scan".
  int _lastMatchedSegment = -1;

  List<LngLat> get coordinates => _coords;
  List<double> get cumulative => _cum;

  /// Total route length in metres.
  double get totalMeters => _cum.isEmpty ? 0 : _cum.last;

  /// Forget the search hint, forcing the next [project] to scan the whole
  /// route. Must be called whenever the underlying route changes — a reroute
  /// or a large GPS jump would otherwise be matched against a stale window.
  void reset() => _lastMatchedSegment = -1;

  /// Project `position` onto the route.
  ///
  /// Uses the rolling window around the previous match when one exists;
  /// pass `forceFullScan: true` to ignore it for this call only.
  RouteProjection project(LngLat position, {bool forceFullScan = false}) {
    if (_coords.length < 2) {
      return const RouteProjection(
        alongMeters: 0,
        bearing: 0,
        offsetMeters: 0,
        segmentIndex: 0,
      );
    }

    final lastSeg = _coords.length - 2;
    final hint = forceFullScan ? -1 : _lastMatchedSegment;
    final iStart = hint >= 0 ? math.max(0, hint - kProjectWindowSegments) : 0;
    final iEnd = hint >= 0
        ? math.min(lastSeg, hint + kProjectWindowSegments)
        : lastSeg;

    var best = double.infinity;
    var bestAlong = _cum.last;
    var bestSeg = lastSeg;

    for (var i = iStart; i <= iEnd; i++) {
      final proj = projectPointOnSegment(position, _coords[i], _coords[i + 1]);
      final d = proj.distanceMeters;
      if (d < best) {
        best = d;
        bestSeg = i;
        bestAlong = _cum[i] + proj.t * (_cum[i + 1] - _cum[i]);
      }
    }

    _lastMatchedSegment = bestSeg;
    return RouteProjection(
      alongMeters: bestAlong,
      bearing: bearingDeg(_coords[bestSeg], _coords[bestSeg + 1]),
      offsetMeters: best,
      segmentIndex: bestSeg,
    );
  }
}
