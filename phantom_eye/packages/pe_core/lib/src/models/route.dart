import '../geo/lng_lat.dart';

/// The 13 maneuver glyphs the guidance UI renders.
///
/// Mirrors `ManeuverKind` in `src/routing.ts:13`.
enum ManeuverKind {
  depart,
  straight,
  left,
  slightLeft,
  sharpLeft,
  right,
  slightRight,
  sharpRight,
  uturn,
  roundabout,
  merge,
  ramp,
  arrive,
}

/// One turn-by-turn instruction.
final class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.distance,
    required this.location,
    required this.kind,
  });

  final String instruction;

  /// Metres travelled during this step.
  final double distance;

  /// Where the maneuver happens.
  final LngLat location;

  final ManeuverKind kind;
}

/// A candidate route: full geometry plus maneuver steps.
final class RouteModel {
  const RouteModel({
    required this.coordinates,
    required this.steps,
    required this.distance,
    required this.duration,
  });

  /// Full geometry.
  final List<LngLat> coordinates;
  final List<RouteStep> steps;

  /// Metres.
  final double distance;

  /// Seconds, as reported by the routing provider (driving network).
  final double duration;
}

enum TravelMode { driving, walking, cycling }

/// Average speeds (m/s) used to estimate walking/cycling time.
///
/// Ported from `MODE_SPEED` in `src/routing.ts:47`. The public OSRM demo only
/// serves the driving network, so for walk/cycle the road geometry is reused
/// and duration is estimated from distance. `driving` is 0, meaning "use the
/// provider's own duration".
const Map<TravelMode, double> kModeSpeedMetersPerSecond = {
  TravelMode.driving: 0,
  TravelMode.walking: 1.4, // ~5 km/h
  TravelMode.cycling: 4.2, // ~15 km/h
};

/// Duration (seconds) for a route travelled in the given mode.
///
/// Ported verbatim from `durationForMode` in `src/routing.ts:57`.
double durationForMode(RouteModel route, TravelMode mode) {
  final speed = kModeSpeedMetersPerSecond[mode] ?? 0;
  return speed > 0 ? route.distance / speed : route.duration;
}
