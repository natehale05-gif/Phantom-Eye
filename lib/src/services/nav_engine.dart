import 'dart:async';

import '../models/geo_point.dart';
import '../models/route_result.dart';

/// A single "tick" of navigation progress, fed to the instruction banner,
/// lane guidance, ETA panel, chase camera, and the CarPlay/Android Auto
/// bridges — this is the one object every nav-consuming widget needs.
class NavProgress {
  const NavProgress({
    required this.puckPoint,
    required this.puckBearingDeg,
    required this.speedMps,
    required this.distanceRemainingMeters,
    required this.durationRemainingSeconds,
    required this.currentManeuverIndex,
    required this.distanceToManeuverMeters,
    required this.progressFraction,
    required this.isOffRoute,
    required this.eta,
    required this.hasArrived,
  });

  final GeoPoint puckPoint;
  final double puckBearingDeg;
  final double speedMps;
  final double distanceRemainingMeters;
  final double durationRemainingSeconds;
  final int currentManeuverIndex;
  final double distanceToManeuverMeters;
  final double progressFraction;
  final bool isOffRoute;
  final DateTime eta;
  final bool hasArrived;
}

/// Drives turn-by-turn navigation state from a stream of raw GPS fixes (or
/// from [simulate], a synthetic "demo drive" that walks the route at a
/// fixed speed — handy for testing/demoing without needing to physically
/// move, and for CarPlay/Android Auto QA).
///
/// This is intentionally *not* tied to any single position source: the UI
/// layer feeds it fixes from `geolocator` in production, or from the
/// simulator during development/demos.
class NavEngine {
  NavEngine(this.route) : _cumulativeDistances = _buildCumulativeDistances(route.path);

  final RouteResult route;
  final List<double> _cumulativeDistances;

  static const double _offRouteThresholdMeters = 40;
  static const double _arrivalThresholdMeters = 20;

  static List<double> _buildCumulativeDistances(List<GeoPoint> path) {
    final distances = List<double>.filled(path.length, 0);
    for (var i = 1; i < path.length; i++) {
      distances[i] = distances[i - 1] + GeoMath.distanceMeters(path[i - 1], path[i]);
    }
    return distances;
  }

  double get totalDistanceMeters =>
      _cumulativeDistances.isEmpty ? 0 : _cumulativeDistances.last;

  /// Projects [fix] onto the route polyline, returning full navigation
  /// progress. [averageSpeedMps] is used only to estimate ETA when the fix
  /// carries no speed of its own (e.g. a coarse/simulated fix).
  NavProgress computeProgress(GeoPoint fix, {double? headingDeg, double? speedMps}) {
    if (route.path.length < 2) {
      return NavProgress(
        puckPoint: fix,
        puckBearingDeg: headingDeg ?? 0,
        speedMps: speedMps ?? 0,
        distanceRemainingMeters: 0,
        durationRemainingSeconds: 0,
        currentManeuverIndex: 0,
        distanceToManeuverMeters: 0,
        progressFraction: 1,
        isOffRoute: true,
        eta: DateTime.now(),
        hasArrived: true,
      );
    }

    var bestDistance = double.infinity;
    var bestSegment = 0;
    var bestT = 0.0;
    GeoPoint bestPoint = route.path.first;

    for (var i = 0; i < route.path.length - 1; i++) {
      final result = GeoMath.closestPointOnSegment(fix, route.path[i], route.path[i + 1]);
      if (result.distanceMeters < bestDistance) {
        bestDistance = result.distanceMeters;
        bestSegment = i;
        bestT = result.t;
        bestPoint = result.point;
      }
    }

    final segmentLength =
        GeoMath.distanceMeters(route.path[bestSegment], route.path[bestSegment + 1]);
    final distanceAlongRoute =
        _cumulativeDistances[bestSegment] + segmentLength * bestT;
    final distanceRemaining = totalDistanceMeters - distanceAlongRoute;

    final bearing = headingDeg ??
        GeoMath.bearingDegrees(route.path[bestSegment], route.path[bestSegment + 1]);

    var maneuverIndex = 0;
    for (var i = 0; i < route.maneuvers.length; i++) {
      final maneuverDistanceAlong = _distanceAlongRouteForPoint(route.maneuvers[i].point);
      maneuverIndex = i;
      if (maneuverDistanceAlong >= distanceAlongRoute - 1) {
        break;
      }
    }
    final nextManeuverDistanceAlong = maneuverIndex < route.maneuvers.length
        ? _distanceAlongRouteForPoint(route.maneuvers[maneuverIndex].point)
        : totalDistanceMeters;
    final distanceToManeuver =
        (nextManeuverDistanceAlong - distanceAlongRoute).clamp(0, totalDistanceMeters);

    final effectiveSpeed = (speedMps != null && speedMps > 0.3)
        ? speedMps
        : (totalDistanceMeters > 0 ? totalDistanceMeters / route.durationSeconds : 1.0);
    final durationRemaining =
        effectiveSpeed > 0 ? distanceRemaining / effectiveSpeed : 0.0;

    final hasArrived = distanceRemaining <= _arrivalThresholdMeters;

    return NavProgress(
      puckPoint: bestPoint,
      puckBearingDeg: bearing,
      speedMps: speedMps ?? effectiveSpeed,
      distanceRemainingMeters: distanceRemaining,
      durationRemainingSeconds: durationRemaining,
      currentManeuverIndex: maneuverIndex,
      distanceToManeuverMeters: distanceToManeuver.toDouble(),
      progressFraction: totalDistanceMeters > 0
          ? (distanceAlongRoute / totalDistanceMeters).clamp(0, 1)
          : 1,
      isOffRoute: bestDistance > _offRouteThresholdMeters,
      eta: DateTime.now().add(Duration(seconds: durationRemaining.round())),
      hasArrived: hasArrived,
    );
  }

  double _distanceAlongRouteForPoint(GeoPoint p) {
    var best = double.infinity;
    var bestDistanceAlong = 0.0;
    for (var i = 0; i < route.path.length - 1; i++) {
      final result = GeoMath.closestPointOnSegment(p, route.path[i], route.path[i + 1]);
      if (result.distanceMeters < best) {
        best = result.distanceMeters;
        final segLen = GeoMath.distanceMeters(route.path[i], route.path[i + 1]);
        bestDistanceAlong = _cumulativeDistances[i] + segLen * result.t;
      }
    }
    return bestDistanceAlong;
  }

  /// Emits synthetic GPS fixes walking the route at [speedMps], for demo
  /// mode / CarPlay-Android Auto QA without needing to physically drive.
  Stream<NavProgress> simulate({double speedMps = 13.0, Duration tickInterval = const Duration(milliseconds: 500)}) {
    late StreamController<NavProgress> controller;
    Timer? timer;
    double distanceTraveled = 0;

    void tick() {
      if (totalDistanceMeters <= 0) {
        controller.close();
        return;
      }
      distanceTraveled += speedMps * (tickInterval.inMilliseconds / 1000);
      final point = _pointAtDistance(distanceTraveled.clamp(0, totalDistanceMeters));
      final progress = computeProgress(point, speedMps: speedMps);
      controller.add(progress);
      if (progress.hasArrived) {
        timer?.cancel();
        controller.close();
      }
    }

    controller = StreamController<NavProgress>(
      onListen: () => timer = Timer.periodic(tickInterval, (_) => tick()),
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  GeoPoint _pointAtDistance(double distance) {
    for (var i = 0; i < _cumulativeDistances.length - 1; i++) {
      if (distance <= _cumulativeDistances[i + 1] || i == _cumulativeDistances.length - 2) {
        final segStart = _cumulativeDistances[i];
        final segEnd = _cumulativeDistances[i + 1];
        final segLen = segEnd - segStart;
        final t = segLen > 0 ? ((distance - segStart) / segLen).clamp(0.0, 1.0) : 0.0;
        final a = route.path[i];
        final b = route.path[i + 1];
        return GeoPoint(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }
    }
    return route.path.last;
  }
}
