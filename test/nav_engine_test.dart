import 'package:flutter_test/flutter_test.dart';
import 'package:phantom_eye/src/models/geo_point.dart';
import 'package:phantom_eye/src/models/route_result.dart';
import 'package:phantom_eye/src/services/nav_engine.dart';

RouteResult _straightRoute() {
  final path = [
    const GeoPoint(0, 0),
    const GeoPoint(0, 0.01),
    const GeoPoint(0, 0.02),
  ];
  return RouteResult(
    profile: TravelProfile.drive,
    source: RouteSource.straightLine,
    path: path,
    maneuvers: [
      RouteManeuver(type: ManeuverType.depart, instruction: 'Depart', point: path.first, distanceMeters: 2223),
      RouteManeuver(type: ManeuverType.arrive, instruction: 'Arrive', point: path.last, distanceMeters: 0),
    ],
    distanceMeters: GeoMath.pathLengthMeters(path),
    durationSeconds: 300,
  );
}

void main() {
  test('computeProgress snaps to the route and reports remaining distance', () {
    final engine = NavEngine(_straightRoute());
    final progress = engine.computeProgress(const GeoPoint(0, 0.01));
    expect(progress.progressFraction, closeTo(0.5, 0.02));
    expect(progress.isOffRoute, isFalse);
    expect(progress.hasArrived, isFalse);
  });

  test('flags off-route when far from the path', () {
    final engine = NavEngine(_straightRoute());
    final progress = engine.computeProgress(const GeoPoint(1, 0.01));
    expect(progress.isOffRoute, isTrue);
  });

  test('reports arrival near the route end', () {
    final engine = NavEngine(_straightRoute());
    final progress = engine.computeProgress(const GeoPoint(0, 0.02));
    expect(progress.hasArrived, isTrue);
  });

  test('simulate() emits progress ticks that reach arrival', () async {
    final engine = NavEngine(_straightRoute());
    final ticks = await engine
        .simulate(speedMps: 500, tickInterval: const Duration(milliseconds: 10))
        .toList();
    expect(ticks, isNotEmpty);
    expect(ticks.last.hasArrived, isTrue);
  });
}
