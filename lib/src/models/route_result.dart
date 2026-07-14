import 'geo_point.dart';

enum TravelProfile { drive, walk, bike }

extension TravelProfileX on TravelProfile {
  String get label => switch (this) {
        TravelProfile.drive => 'Drive',
        TravelProfile.walk => 'Walk',
        TravelProfile.bike => 'Bike',
      };

  /// Valhalla "costing" model name.
  String get valhallaCosting => switch (this) {
        TravelProfile.drive => 'auto',
        TravelProfile.walk => 'pedestrian',
        TravelProfile.bike => 'bicycle',
      };

  /// OSRM profile name (public demo server only actually hosts `driving`).
  String get osrmProfile => switch (this) {
        TravelProfile.drive => 'driving',
        TravelProfile.walk => 'foot',
        TravelProfile.bike => 'bike',
      };
}

enum ManeuverType {
  depart,
  arrive,
  straight,
  turnLeft,
  turnRight,
  turnSlightLeft,
  turnSlightRight,
  turnSharpLeft,
  turnSharpRight,
  uturn,
  merge,
  roundabout,
  fork,
  keepLeft,
  keepRight,
}

class RouteManeuver {
  const RouteManeuver({
    required this.type,
    required this.instruction,
    required this.point,
    required this.distanceMeters,
    this.streetName,
  });

  final ManeuverType type;
  final String instruction;
  final GeoPoint point;

  /// Distance (meters) from this maneuver to the next one.
  final double distanceMeters;
  final String? streetName;
}

/// Which backend actually produced a route — surfaced in the UI as a small
/// "via Valhalla" / "via OSRM" / "straight line (offline estimate)" label
/// so users understand why a backcountry route might be a rough estimate.
enum RouteSource { valhalla, osrm, straightLine }

class RouteResult {
  const RouteResult({
    required this.profile,
    required this.source,
    required this.path,
    required this.maneuvers,
    required this.distanceMeters,
    required this.durationSeconds,
    this.elevationGainMeters,
    this.elevationLossMeters,
    this.elevationProfile,
  });

  final TravelProfile profile;
  final RouteSource source;
  final List<GeoPoint> path;
  final List<RouteManeuver> maneuvers;
  final double distanceMeters;
  final double durationSeconds;
  final double? elevationGainMeters;
  final double? elevationLossMeters;
  final List<ElevationPoint>? elevationProfile;

  RouteResult copyWith({
    List<ElevationPoint>? elevationProfile,
    double? elevationGainMeters,
    double? elevationLossMeters,
  }) {
    return RouteResult(
      profile: profile,
      source: source,
      path: path,
      maneuvers: maneuvers,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      elevationLossMeters: elevationLossMeters ?? this.elevationLossMeters,
      elevationProfile: elevationProfile ?? this.elevationProfile,
    );
  }
}
