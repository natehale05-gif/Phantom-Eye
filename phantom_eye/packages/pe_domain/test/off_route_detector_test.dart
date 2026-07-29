import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

/// A hand-cranked clock so deviation timing is deterministic.
final class FakeClock {
  DateTime now = DateTime(2026, 7, 29, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('OffRouteDetector', () {
    late FakeClock clock;
    late OffRouteDetector detector;

    setUp(() {
      clock = FakeClock();
      detector = OffRouteDetector(clock: clock.call);
    });

    test('on-route never triggers', () {
      for (var i = 0; i < 20; i++) {
        expect(detector.update(offsetMeters: 5, arrived: false), isFalse);
        clock.advance(const Duration(seconds: 1));
      }
    });

    test('an isolated noisy fix never triggers', () {
      expect(detector.update(offsetMeters: 80, arrived: false), isFalse);
      clock.advance(const Duration(milliseconds: 500));
      // Back on route well before the 3 s confirm window.
      expect(detector.update(offsetMeters: 8, arrived: false), isFalse);
      clock.advance(const Duration(seconds: 10));
      expect(detector.update(offsetMeters: 8, arrived: false), isFalse);
    });

    test('sustained deviation triggers once the confirm window elapses', () {
      expect(detector.update(offsetMeters: 80, arrived: false), isFalse);
      clock.advance(const Duration(seconds: 1));
      expect(detector.update(offsetMeters: 90, arrived: false), isFalse);
      clock.advance(const Duration(seconds: 2)); // now at 3 s
      expect(detector.update(offsetMeters: 95, arrived: false), isTrue);
    });

    test('coming back on route restarts the clock for the next episode', () {
      detector.update(offsetMeters: 80, arrived: false);
      clock.advance(const Duration(milliseconds: 2500));
      detector.update(offsetMeters: 5, arrived: false); // resets
      clock.advance(const Duration(milliseconds: 100));

      // New episode starts here; 2.5 s of the old one must not carry over.
      expect(detector.update(offsetMeters: 80, arrived: false), isFalse);
      clock.advance(const Duration(milliseconds: 2900));
      expect(detector.update(offsetMeters: 80, arrived: false), isFalse);
      clock.advance(const Duration(milliseconds: 200));
      expect(detector.update(offsetMeters: 80, arrived: false), isTrue);
    });

    test('the cooldown prevents back-to-back reroutes', () {
      clock.advance(const Duration(seconds: 1));
      detector.update(offsetMeters: 80, arrived: false);
      clock.advance(const Duration(seconds: 4));
      expect(detector.update(offsetMeters: 80, arrived: false), isTrue);

      detector
        ..beginReroute()
        ..endReroute()
        ..reset();

      // Still off route; a new episode confirms, but the cooldown blocks it.
      expect(detector.update(offsetMeters: 80, arrived: false), isFalse);
      clock.advance(const Duration(seconds: 4));
      expect(
        detector.update(offsetMeters: 80, arrived: false),
        isFalse,
        reason: 'within the 5 s cooldown',
      );

      clock.advance(const Duration(seconds: 2)); // past cooldown
      expect(detector.update(offsetMeters: 80, arrived: false), isTrue);
    });

    test('an in-flight reroute suppresses further triggers', () {
      detector.update(offsetMeters: 80, arrived: false);
      clock.advance(const Duration(seconds: 4));
      expect(detector.update(offsetMeters: 80, arrived: false), isTrue);

      detector.beginReroute();
      expect(detector.isRerouting, isTrue);

      clock.advance(const Duration(seconds: 30));
      expect(
        detector.update(offsetMeters: 80, arrived: false),
        isFalse,
        reason: 'a slow routing response must not overlap itself',
      );

      detector.endReroute();
      expect(detector.isRerouting, isFalse);
    });

    test('arrival suppresses rerouting entirely', () {
      for (var i = 0; i < 20; i++) {
        expect(detector.update(offsetMeters: 500, arrived: true), isFalse);
        clock.advance(const Duration(seconds: 1));
      }
    });

    test('exactly at the distance threshold is treated as on-route', () {
      expect(
        detector.update(offsetMeters: kOffRouteMeters, arrived: false),
        isFalse,
      );
      clock.advance(const Duration(seconds: 10));
      expect(
        detector.update(offsetMeters: kOffRouteMeters, arrived: false),
        isFalse,
      );
      expect(detector.isOffRoute, isFalse);
    });
  });

  group('ArrivalDetector', () {
    test('latches exactly once', () {
      final d = ArrivalDetector();
      expect(d.update(100), isFalse);
      expect(d.update(20), isTrue);
      expect(d.update(10), isFalse, reason: 'must not re-fire on jitter');
      expect(d.update(30), isFalse);
      expect(d.hasArrived, isTrue);
    });

    test('reset re-arms for the next trip', () {
      final d = ArrivalDetector()..update(5);
      d.reset();
      expect(d.hasArrived, isFalse);
      expect(d.update(5), isTrue);
    });

    test('the threshold boundary is exclusive', () {
      expect(ArrivalDetector().update(kArrivalMeters), isFalse);
      expect(ArrivalDetector().update(kArrivalMeters - 0.01), isTrue);
    });
  });
}
