import 'package:pe_core/pe_core.dart';
import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

final class FakeClock {
  DateTime now = DateTime(2026, 7, 29, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('MinInterval', () {
    test('first call always fires', () {
      expect(MinInterval(const Duration(seconds: 1)).tryFire(), isTrue);
    });

    test('rate-limits a fast burst', () {
      final clock = FakeClock();
      final gate = MinInterval(
        const Duration(milliseconds: 250),
        clock: clock.call,
      );

      var fired = 0;
      for (var i = 0; i <= 20; i++) {
        if (gate.tryFire()) fired++;
        clock.advance(const Duration(milliseconds: 50));
      }
      // Fires at 0, 250, 500, 750, 1000 ms.
      expect(fired, 5);
    });

    test('is invisible at normal GPS cadence', () {
      final clock = FakeClock();
      final gate = MinInterval(
        const Duration(milliseconds: 250),
        clock: clock.call,
      );

      var fired = 0;
      for (var i = 0; i < 6; i++) {
        if (gate.tryFire()) fired++;
        clock.advance(const Duration(seconds: 1));
      }
      expect(fired, 6, reason: '1 Hz fixes are all well past the interval');
    });

    test('isReady does not consume the slot', () {
      final clock = FakeClock();
      final gate = MinInterval(const Duration(seconds: 1), clock: clock.call);
      expect(gate.isReady, isTrue);
      expect(gate.isReady, isTrue);
      expect(gate.tryFire(), isTrue);
      expect(gate.isReady, isFalse);
    });

    test('reset re-arms immediately', () {
      final clock = FakeClock();
      final gate = MinInterval(const Duration(seconds: 10), clock: clock.call);
      gate.tryFire();
      expect(gate.tryFire(), isFalse);
      gate.reset();
      expect(gate.tryFire(), isTrue);
    });
  });

  group('CameraPolicy throttles (the anti-overheat fix)', () {
    late FakeClock clock;
    late CameraPolicy policy;

    setUp(() {
      clock = FakeClock();
      policy = CameraPolicy(clock: clock.call);
    });

    test('follow re-aim is gated to 800 ms', () {
      var allowed = 0;
      for (var i = 0; i <= 16; i++) {
        if (policy.allowFollowReaim()) allowed++;
        clock.advance(const Duration(milliseconds: 100));
      }
      // 0, 800, 1600 ms.
      expect(allowed, 3);
    });

    test('height refine is gated to 400 ms', () {
      var allowed = 0;
      for (var i = 0; i <= 12; i++) {
        if (policy.allowHeightRefine()) allowed++;
        clock.advance(const Duration(milliseconds: 100));
      }
      // 0, 400, 800, 1200 ms.
      expect(allowed, 4);
    });

    test('route snap is gated to 250 ms', () {
      var allowed = 0;
      for (var i = 0; i <= 10; i++) {
        if (policy.allowRouteSnap()) allowed++;
        clock.advance(const Duration(milliseconds: 100));
      }
      // Fires at 0, then the first sample at/after each +250 ms: 300, 600,
      // 900. (Sampling every 100 ms means the gate opens between samples,
      // so real firings land later than exact multiples of the interval.)
      expect(allowed, 4);
    });

    test('the three gates are independent', () {
      expect(policy.allowFollowReaim(), isTrue);
      expect(policy.allowHeightRefine(), isTrue);
      expect(policy.allowRouteSnap(), isTrue);

      clock.advance(const Duration(milliseconds: 300));
      expect(policy.allowRouteSnap(), isTrue, reason: '250 ms elapsed');
      expect(policy.allowHeightRefine(), isFalse, reason: 'needs 400 ms');
      expect(policy.allowFollowReaim(), isFalse, reason: 'needs 800 ms');
    });
  });

  group('CameraPolicy chase camera', () {
    late FakeClock clock;
    late CameraPolicy policy;

    setUp(() {
      clock = FakeClock();
      policy = CameraPolicy(clock: clock.call);
    });

    test('per-fix glide is LINEAR — eased curves stutter between fixes', () {
      final cmd = policy.navCameraFor(90)!;
      expect(cmd.curve, CameraCurve.linear);
      expect(cmd.duration, kNavCameraGlide);
    });

    test('cinematic entrance is eased and longer', () {
      final cmd = policy.navCameraFor(90, cinematic: true)!;
      expect(cmd.curve, CameraCurve.eased);
      expect(cmd.duration, kNavCameraCinematic);
    });

    test('uses the ported chase framing', () {
      final cmd = policy.navCameraFor(45)!;
      expect(cmd.backMeters, kNavCameraBackMeters);
      expect(cmd.upMeters, kNavCameraUpMeters);
      expect(cmd.pitchDegrees, kNavCameraPitchDegrees);
      expect(cmd.courseDegrees, 45);
    });

    test('manual interaction suspends the chase camera', () {
      expect(policy.navCameraFor(10), isNotNull);
      policy.onManualInteraction();
      expect(policy.isManualOverride, isTrue);
      expect(
        policy.navCameraFor(20),
        isNull,
        reason: 'free-roam must not be fought by the chase camera',
      );
    });

    test('course keeps updating while suspended, so resume is not stale', () {
      policy.onManualInteraction();
      policy.navCameraFor(123);
      expect(policy.lastCourseDegrees, 123);
    });

    test('resumes exactly once, 8 s after the last gesture', () {
      policy.onManualInteraction();

      clock.advance(const Duration(seconds: 5));
      expect(policy.shouldResumeAfterFreeRoam(), isFalse);

      clock.advance(const Duration(seconds: 3)); // now 8 s
      expect(policy.shouldResumeAfterFreeRoam(), isTrue);
      expect(
        policy.shouldResumeAfterFreeRoam(),
        isFalse,
        reason: 'must fire once per episode',
      );
      expect(policy.isManualOverride, isFalse);
      expect(policy.navCameraFor(30), isNotNull);
    });

    test('further gestures extend the free-roam window', () {
      policy.onManualInteraction();
      clock.advance(const Duration(seconds: 7));
      policy.onManualInteraction(); // restarts the 8 s
      clock.advance(const Duration(seconds: 5));
      expect(policy.shouldResumeAfterFreeRoam(), isFalse);
      clock.advance(const Duration(seconds: 4));
      expect(policy.shouldResumeAfterFreeRoam(), isTrue);
    });

    test('follow camera respects the 800 ms gate unless instant', () {
      expect(policy.followCameraFor(0), isNotNull);
      expect(policy.followCameraFor(0), isNull, reason: 'throttled');
      expect(
        policy.followCameraFor(0, instant: true),
        isNotNull,
        reason: 'instant bypasses the gate',
      );
    });

    test('follow uses its own wider framing', () {
      final cmd = policy.followCameraFor(0, instant: true)!;
      expect(cmd.backMeters, kFollowCameraBackMeters);
      expect(cmd.pitchDegrees, kFollowCameraPitchDegrees);
    });

    test('reset clears gates and override', () {
      policy
        ..allowFollowReaim()
        ..onManualInteraction()
        ..reset();
      expect(policy.isManualOverride, isFalse);
      expect(policy.allowFollowReaim(), isTrue);
    });
  });

  group('RouteSnapper', () {
    final route = [
      for (var i = 0; i < 100; i++) LngLat(-122.0 + i * 0.0001, 37.0),
    ];

    test('bends the route to the live position and trims what is behind', () {
      final projector = RouteProjector(coordinates: route);
      const pos = LngLat(-121.995, 37.00001);
      final proj = projector.project(pos);

      final snapped = const RouteSnapper().snap(
        routeCoordinates: route,
        position: pos,
        projection: proj,
      )!;

      expect(snapped.first, pos, reason: 'near end touches you');
      expect(snapped.last, route.last, reason: 'far end is unchanged');
      expect(snapped.length, lessThan(route.length), reason: 'trimmed behind');
    });

    test('refuses to bend when genuinely off-route', () {
      final projector = RouteProjector(coordinates: route);
      // ~0.002 deg of latitude off ~= 220 m, well past the 30 m limit.
      const pos = LngLat(-121.995, 37.002);
      final proj = projector.project(pos);
      expect(proj.offsetMeters, greaterThan(kRouteSnapMaxOffsetMeters));

      expect(
        const RouteSnapper().snap(
          routeCoordinates: route,
          position: pos,
          projection: proj,
        ),
        isNull,
        reason: 'a long connector would draw a lie across the map',
      );
    });

    test('degenerate route returns null', () {
      expect(
        const RouteSnapper().snap(
          routeCoordinates: const [LngLat(0, 0)],
          position: const LngLat(0, 0),
          projection: const RouteProjection(
            alongMeters: 0,
            bearing: 0,
            offsetMeters: 0,
            segmentIndex: 0,
          ),
        ),
        isNull,
      );
    });
  });
}
