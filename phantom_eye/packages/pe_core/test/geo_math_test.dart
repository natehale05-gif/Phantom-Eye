import 'package:pe_core/pe_core.dart';
import 'package:test/test.dart';

void main() {
  group('haversine', () {
    test('is zero for identical points', () {
      const p = LngLat(-122.4194, 37.7749);
      expect(haversine(p, p), closeTo(0, 1e-9));
    });

    test('matches a known great-circle distance (SF -> NYC)', () {
      const sf = LngLat(-122.4194, 37.7749);
      const nyc = LngLat(-74.0060, 40.7128);
      // ~4129 km; allow 1 km of slack for the spherical approximation.
      expect(haversine(sf, nyc) / 1000, closeTo(4129, 1));
    });

    test('is symmetric', () {
      const a = LngLat(-122.0, 37.0);
      const b = LngLat(-121.9, 37.1);
      expect(haversine(a, b), closeTo(haversine(b, a), 1e-9));
    });

    test('one degree of latitude is ~111 km anywhere', () {
      for (final lat in [0.0, 30.0, 60.0]) {
        final d = haversine(LngLat(0, lat), LngLat(0, lat + 1));
        expect(d / 1000, closeTo(111.19, 0.1));
      }
    });
  });

  group('bearingDeg', () {
    test('due north is 0', () {
      expect(
        bearingDeg(const LngLat(0, 0), const LngLat(0, 1)),
        closeTo(0, 1e-9),
      );
    });

    test('due east is 90', () {
      expect(
        bearingDeg(const LngLat(0, 0), const LngLat(1, 0)),
        closeTo(90, 1e-9),
      );
    });

    test('due south is 180', () {
      expect(
        bearingDeg(const LngLat(0, 0), const LngLat(0, -1)).abs(),
        closeTo(180, 1e-9),
      );
    });

    test('due west is -90 (range is -180..180, matching the TS original)', () {
      expect(
        bearingDeg(const LngLat(0, 0), const LngLat(-1, 0)),
        closeTo(-90, 1e-9),
      );
    });
  });

  group('normalizeBearing / normalizeAngleDelta', () {
    test('normalizeBearing wraps into 0..360', () {
      expect(normalizeBearing(-90), closeTo(270, 1e-9));
      expect(normalizeBearing(450), closeTo(90, 1e-9));
      expect(normalizeBearing(0), closeTo(0, 1e-9));
    });

    test('normalizeAngleDelta wraps into -180..180', () {
      expect(normalizeAngleDelta(190), closeTo(-170, 1e-9));
      expect(normalizeAngleDelta(-190), closeTo(170, 1e-9));
      expect(normalizeAngleDelta(45), closeTo(45, 1e-9));
    });
  });

  group('destinationPoint', () {
    test('north increases latitude, holds longitude', () {
      final p = destinationPoint(const LngLat(-122, 37), 0, 100);
      expect(p.lat, greaterThan(37));
      expect(p.lon, closeTo(-122, 1e-9));
    });

    test('east increases longitude, roughly holds latitude', () {
      final p = destinationPoint(const LngLat(-122, 37), 90, 100);
      expect(p.lon, greaterThan(-122));
      expect(p.lat, closeTo(37, 1e-3));
    });

    test('round-trips: 100 m out and back returns to origin', () {
      const origin = LngLat(-122, 37);
      final out = destinationPoint(origin, 42, 100);
      final back = destinationPoint(out, 42 + 180, 100);
      expect(haversine(origin, back), lessThan(0.5));
    });

    test('travels the requested distance', () {
      const origin = LngLat(-122, 37);
      final p = destinationPoint(origin, 33, 250);
      expect(haversine(origin, p), closeTo(250, 0.5));
    });
  });

  group('cumulativeDistances', () {
    test('starts at zero and is monotonic', () {
      final pts = [
        const LngLat(-122, 37),
        const LngLat(-122, 37.001),
        const LngLat(-122, 37.002),
      ];
      final cum = cumulativeDistances(pts);
      expect(cum.length, pts.length);
      expect(cum.first, 0);
      for (var i = 1; i < cum.length; i++) {
        expect(cum[i], greaterThan(cum[i - 1]));
      }
    });

    test('total equals the sum of leg lengths', () {
      final pts = [
        const LngLat(-122, 37),
        const LngLat(-122, 37.01),
        const LngLat(-121.99, 37.01),
      ];
      final expected = haversine(pts[0], pts[1]) + haversine(pts[1], pts[2]);
      expect(cumulativeDistances(pts).last, closeTo(expected, 1e-6));
    });

    test('single point yields [0]', () {
      expect(cumulativeDistances([const LngLat(0, 0)]), [0]);
    });
  });

  group('projectPointOnSegment', () {
    test('a point on the segment projects with ~zero offset', () {
      const a = LngLat(-122, 37);
      const b = LngLat(-122, 37.01);
      final mid = lerpLngLat(a, b, 0.5);
      final proj = projectPointOnSegment(mid, a, b);
      expect(proj.t, closeTo(0.5, 1e-6));
      expect(proj.distanceMeters, lessThan(0.5));
    });

    test('clamps t before the start of the segment', () {
      const a = LngLat(-122, 37);
      const b = LngLat(-122, 37.01);
      final proj = projectPointOnSegment(const LngLat(-122, 36.99), a, b);
      expect(proj.t, 0);
    });

    test('clamps t past the end of the segment', () {
      const a = LngLat(-122, 37);
      const b = LngLat(-122, 37.01);
      final proj = projectPointOnSegment(const LngLat(-122, 37.02), a, b);
      expect(proj.t, 1);
    });

    test('reports perpendicular offset in metres', () {
      // ~0.001 deg of latitude east of a due-north segment at lat 37.
      const a = LngLat(-122, 37);
      const b = LngLat(-122, 37.01);
      const off = LngLat(-122 + 0.001 / 0.7986, 37.005); // /cos(37) => ~111 m
      final proj = projectPointOnSegment(off, a, b);
      expect(proj.distanceMeters, closeTo(111.3, 5));
    });

    test('degenerate (zero-length) segment does not divide by zero', () {
      const a = LngLat(-122, 37);
      final proj = projectPointOnSegment(const LngLat(-122, 37.001), a, a);
      expect(proj.distanceMeters.isFinite, isTrue);
    });
  });

  group('formatters', () {
    test('formatDistance uses feet below 1000 ft, rounded to 10', () {
      expect(formatDistance(0), '0 ft');
      expect(formatDistance(30.48), '100 ft'); // 100 ft exactly
      expect(formatDistance(100), '330 ft');
    });

    test('formatDistance switches to miles at 1000 ft', () {
      // The threshold is on raw feet, but display rounds to the nearest 10 —
      // so just under the boundary it reads "1000 ft" (997.4 ft rounded),
      // and at or above it flips to miles. This quirk is inherited from
      // formatDistance in src/routing.ts and is preserved deliberately.
      expect(formatDistance(304), '1000 ft');
      expect(formatDistance(305), '0.2 mi');
      expect(formatDistance(1609.344), '1.0 mi');
      expect(formatDistance(8046.72), '5.0 mi');
    });

    test('formatDistance drops the decimal at 10 mi and above', () {
      expect(formatDistance(16093.44), '10 mi');
      expect(formatDistance(160934.4), '100 mi');
    });

    test('formatDuration', () {
      expect(formatDuration(0), '0 min');
      expect(formatDuration(59), '1 min');
      expect(formatDuration(600), '10 min');
      expect(formatDuration(3600), '1 hr');
      expect(formatDuration(3900), '1 hr 5 min');
      expect(formatDuration(7200), '2 hr');
    });

    test('arrivalClock renders 12-hour time', () {
      final base = DateTime(2026, 7, 29, 14, 40);
      expect(arrivalClock(300, now: base), '2:45 PM');
      expect(arrivalClock(0, now: DateTime(2026, 7, 29, 0, 5)), '12:05 AM');
      expect(arrivalClock(0, now: DateTime(2026, 7, 29, 12, 0)), '12:00 PM');
    });

    test('formatRelativeTime', () {
      final now = DateTime(2026, 7, 29, 12, 0);
      expect(formatRelativeTime(now, now: now), 'just now');
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 12)), now: now),
        '12 min ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 1)), now: now),
        '1 hr ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3 hrs ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2 days ago',
      );
    });
  });

  group('LatLngBounds', () {
    test('contains every point it was built from', () {
      final pts = [
        const LngLat(-122, 37),
        const LngLat(-121, 38),
        const LngLat(-123, 36),
      ];
      final b = LatLngBounds.containing(pts)!;
      for (final p in pts) {
        expect(b.contains(p), isTrue);
      }
    });

    test('is null for an empty list', () {
      expect(LatLngBounds.containing(const []), isNull);
    });

    test('ignores non-finite points', () {
      final b = LatLngBounds.containing([
        const LngLat(-122, 37),
        const LngLat(double.nan, 5),
      ]);
      expect(b, isNotNull);
      expect(b!.south, 37);
    });
  });

  group('LruCache', () {
    test('evicts the oldest entry past capacity', () {
      final c = LruCache<String, int>(3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);
      expect(c.length, 3);
      c.put('d', 4);
      expect(c.containsKey('a'), isFalse);
      expect(c.length, 3);
    });

    test('a hit bumps recency so the next-oldest is evicted instead', () {
      final c = LruCache<String, int>(3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);
      c.get('a'); // touch
      c.put('d', 4);
      expect(c.containsKey('a'), isTrue, reason: 'touched entry survives');
      expect(c.containsKey('b'), isFalse, reason: 'next-oldest evicted');
    });

    test('re-putting an existing key does not grow the cache', () {
      final c = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('a', 2);
      expect(c.length, 1);
      expect(c.get('a'), 2);
    });
  });
}
