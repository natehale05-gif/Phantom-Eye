import 'package:flutter_test/flutter_test.dart';
import 'package:phantom_eye/src/models/geo_point.dart';

void main() {
  group('GeoMath.distanceMeters', () {
    test('is ~0 for identical points', () {
      const p = GeoPoint(37.7749, -122.4194);
      expect(GeoMath.distanceMeters(p, p), closeTo(0, 0.001));
    });

    test('matches known SF -> LA great-circle distance', () {
      const sf = GeoPoint(37.7749, -122.4194);
      const la = GeoPoint(34.0522, -118.2437);
      final meters = GeoMath.distanceMeters(sf, la);
      // Known great-circle distance is ~559 km; allow generous tolerance.
      expect(meters / 1000, closeTo(559, 10));
    });
  });

  group('GeoMath.bearingDegrees', () {
    test('due north is 0 degrees', () {
      const a = GeoPoint(0, 0);
      const b = GeoPoint(1, 0);
      expect(GeoMath.bearingDegrees(a, b), closeTo(0, 0.01));
    });

    test('due east is ~90 degrees', () {
      const a = GeoPoint(0, 0);
      const b = GeoPoint(0, 1);
      expect(GeoMath.bearingDegrees(a, b), closeTo(90, 0.01));
    });
  });

  group('GeoMath.angleDiffDegrees', () {
    test('handles wraparound correctly', () {
      expect(GeoMath.angleDiffDegrees(350, 10), closeTo(20, 0.01));
      expect(GeoMath.angleDiffDegrees(10, 350), closeTo(-20, 0.01));
    });
  });

  group('GeoMath.closestPointOnSegment', () {
    test('projects onto the segment midpoint', () {
      const a = GeoPoint(0, 0);
      const b = GeoPoint(0, 1);
      const p = GeoPoint(0.001, 0.5);
      final result = GeoMath.closestPointOnSegment(p, a, b);
      expect(result.t, closeTo(0.5, 0.01));
    });

    test('clamps t to [0, 1] beyond segment ends', () {
      const a = GeoPoint(0, 0);
      const b = GeoPoint(0, 1);
      const p = GeoPoint(0, 2);
      final result = GeoMath.closestPointOnSegment(p, a, b);
      expect(result.t, 1.0);
    });
  });

  group('GeoMath.destinationPoint', () {
    test('round-trips with bearing/distance', () {
      const origin = GeoPoint(45, -122);
      final dest = GeoMath.destinationPoint(origin, 90, 10000);
      final distanceBack = GeoMath.distanceMeters(origin, dest);
      expect(distanceBack, closeTo(10000, 5));
    });
  });
}
