import 'package:pe_core/pe_core.dart';
import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

/// A long, finely-sampled route: 2000 points ~20 m apart running northeast.
List<LngLat> _longRoute() => [
  for (var i = 0; i < 2000; i++)
    LngLat(-122.0 + i * 0.0001, 37.0 + i * 0.00008),
];

LngLat _midpointOfSegment(List<LngLat> route, int seg) =>
    lerpLngLat(route[seg], route[seg + 1], 0.5);

void main() {
  group('RouteProjector windowing', () {
    test('windowed result matches a full scan at the same position', () {
      final route = _longRoute();
      const seg = 1000;
      final pos = _midpointOfSegment(route, seg);

      final full = RouteProjector(
        coordinates: route,
      ).project(pos, forceFullScan: true);

      final windowed = RouteProjector(coordinates: route)
        ..project(_midpointOfSegment(route, seg), forceFullScan: true);
      final again = windowed.project(pos);

      expect(again.segmentIndex, full.segmentIndex);
      expect(again.alongMeters, closeTo(full.alongMeters, 1e-6));
      expect(again.offsetMeters, closeTo(full.offsetMeters, 1e-6));
      expect(again.bearing, closeTo(full.bearing, 1e-9));
    });

    test(
      'tracks a full monotonic drive with zero divergence from full scan',
      () {
        final route = _longRoute();
        final projector = RouteProjector(coordinates: route);
        final reference = RouteProjector(coordinates: route);

        var mismatches = 0;
        for (var seg = 0; seg < route.length - 1; seg += 25) {
          final pos = _midpointOfSegment(route, seg);
          final windowed = projector.project(pos);
          final full = reference.project(pos, forceFullScan: true);
          if (windowed.segmentIndex != full.segmentIndex) mismatches++;
        }
        expect(mismatches, 0);
      },
    );

    test('advances the hint as the vehicle moves', () {
      final route = _longRoute();
      final projector = RouteProjector(coordinates: route);

      final start = projector.project(_midpointOfSegment(route, 0));
      final later = projector.project(_midpointOfSegment(route, 500));
      expect(later.segmentIndex, greaterThan(start.segmentIndex));
    });

    test('a jump beyond the window is mismatched until reset — which is '
        'exactly why reset() is called on every route change', () {
      final route = _longRoute();
      final projector = RouteProjector(coordinates: route)
        ..project(_midpointOfSegment(route, 1500));

      // Teleport far outside the +/-40 window without resetting.
      final stale = projector.project(_midpointOfSegment(route, 100));
      expect(
        stale.segmentIndex,
        isNot(100),
        reason: 'window cannot see that far — this is the failure mode',
      );

      // reset() restores correctness, as a reroute would.
      projector.reset();
      final fresh = projector.project(_midpointOfSegment(route, 100));
      expect(fresh.segmentIndex, 100);
    });

    test('alongMeters increases monotonically along the route', () {
      final route = _longRoute();
      final projector = RouteProjector(coordinates: route);
      var prev = -1.0;
      for (var seg = 0; seg < 900; seg += 30) {
        final p = projector.project(_midpointOfSegment(route, seg));
        expect(p.alongMeters, greaterThan(prev));
        prev = p.alongMeters;
      }
    });

    test('offset is ~zero on the route and grows off it', () {
      final route = _longRoute();
      final projector = RouteProjector(coordinates: route);
      final on = projector.project(_midpointOfSegment(route, 300));
      expect(on.offsetMeters, lessThan(1));

      final near = _midpointOfSegment(route, 300);
      final off = projector.project(LngLat(near.lon, near.lat + 0.001));
      expect(off.offsetMeters, greaterThan(50));
    });

    test('degenerate routes do not throw', () {
      expect(
        RouteProjector(
          coordinates: [const LngLat(0, 0)],
        ).project(const LngLat(0, 0)).alongMeters,
        0,
      );
      expect(
        RouteProjector(
          coordinates: const [],
        ).project(const LngLat(0, 0)).segmentIndex,
        0,
      );
    });

    test('totalMeters matches the cumulative tail', () {
      final route = _longRoute();
      final projector = RouteProjector(coordinates: route);
      expect(projector.totalMeters, closeTo(projector.cumulative.last, 1e-9));
    });
  });
}
