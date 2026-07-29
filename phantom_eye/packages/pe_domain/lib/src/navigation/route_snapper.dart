import 'package:pe_core/pe_core.dart';

import 'route_projector.dart';

/// Maximum offset at which the route is still bent to the live position.
///
/// Ported from `ROUTE_SNAP_MAX_OFFSET_M` in `src/globe.ts`. Beyond this you
/// are genuinely off-route (and about to be rerouted), so stretching a long
/// connector out to the position would draw a lie across the map.
const double kRouteSnapMaxOffsetMeters = 30;

/// Bends the drawn route so its near end touches the live GPS position and
/// trims away what is now behind you.
///
/// This is the Apple-Maps "the line disappears behind you" behaviour, and it
/// is deliberately the *route* that moves, not the location puck. An earlier
/// iteration of the legacy app snapped the puck onto the road instead; that
/// was reverted because it made the dot visibly lie about where you were
/// whenever GPS sat a little off the carriageway. Keep this direction.
final class RouteSnapper {
  const RouteSnapper({this.maxOffsetMeters = kRouteSnapMaxOffsetMeters});

  final double maxOffsetMeters;

  /// Produce the polyline to draw, given the full route and where the user is.
  ///
  /// Returns null when the projection is too far off-route to bend, in which
  /// case the caller should keep drawing the unmodified route.
  List<LngLat>? snap({
    required List<LngLat> routeCoordinates,
    required LngLat position,
    required RouteProjection projection,
  }) {
    if (routeCoordinates.length < 2) return null;
    if (projection.offsetMeters >= maxOffsetMeters) return null;

    final tailStart = projection.segmentIndex + 1;
    if (tailStart >= routeCoordinates.length) return [position];

    return [position, ...routeCoordinates.sublist(tailStart)];
  }
}

/// Distance from the destination at which arrival is declared.
///
/// Ported from the `remaining < 25` check in `src/navigation.ts`.
const double kArrivalMeters = 25;

/// How long the "You have arrived" state lingers before guidance auto-ends.
const Duration kArrivalLinger = Duration(milliseconds: 2600);

/// Latches arrival exactly once per trip.
///
/// The latch matters: without it, GPS jitter around the destination
/// repeatedly re-fires arrival, which in the legacy app meant the
/// end-of-trip teardown could run more than once.
final class ArrivalDetector {
  ArrivalDetector({this.arrivalMeters = kArrivalMeters});

  final double arrivalMeters;
  bool _arrived = false;

  bool get hasArrived => _arrived;

  /// Returns true on the single fix that first crosses the threshold.
  bool update(double remainingMeters) {
    if (_arrived) return false;
    if (remainingMeters >= arrivalMeters) return false;
    _arrived = true;
    return true;
  }

  void reset() => _arrived = false;
}
