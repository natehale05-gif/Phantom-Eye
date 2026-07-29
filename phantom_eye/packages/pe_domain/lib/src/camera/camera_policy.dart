import 'package:pe_core/pe_core.dart';

/// Minimum spacing between follow-camera re-aims.
///
/// Ported from `FOLLOW_MIN_INTERVAL_MS` in `src/globe.ts`. **This constant is
/// the phone-overheating fix.** Every re-aim forces the tile engine to
/// re-cull and re-stream at a new frustum; GPS fixes arrive far faster than
/// that work can be justified, and removing this gate is what previously
/// pinned the GPU for as long as the app was open. It is kept even on the
/// cheap vector engine, because the underlying reasoning (don't restream on
/// every fix) holds there too.
const Duration kFollowReaimInterval = Duration(milliseconds: 800);

/// Minimum spacing between surface-height refinements.
///
/// Ported from `HEIGHT_REFINE_MIN_INTERVAL_MS` in `src/globe.ts`. On the
/// photoreal engine each refinement is a synchronous offscreen render and
/// readback; on a vector engine it is a cheap terrain query, but the gate
/// costs nothing to keep and bounds the worst case.
const Duration kHeightRefineInterval = Duration(milliseconds: 400);

/// Minimum spacing between route re-snaps.
///
/// Ported from `ROUTE_SNAP_MIN_INTERVAL_MS` in `src/globe.ts`. Well under
/// normal GPS cadence, so the "route bends to you" effect stays visually
/// continuous while the recompute is bounded.
const Duration kRouteSnapInterval = Duration(milliseconds: 250);

/// How long the chase camera stays surrendered after a manual gesture.
///
/// Ported from `NAV_RESUME_DELAY_MS` in `src/globe.ts`.
const Duration kNavResumeDelay = Duration(seconds: 8);

/// Duration of the per-fix chase-camera glide.
///
/// Ported from `NAV_CAMERA_GLIDE_S` in `src/globe.ts`. Paired with
/// [CameraCurve.linear] below — see that doc for why the curve matters.
const Duration kNavCameraGlide = Duration(milliseconds: 600);

/// Duration of the cinematic entrance / free-roam resume flight.
const Duration kNavCameraCinematic = Duration(milliseconds: 1200);

/// How the camera interpolates toward a new pose.
enum CameraCurve {
  /// Constant velocity. **Required for the per-fix chase camera.** Eased
  /// curves decelerate into each target, so with a new fix arriving before
  /// the previous glide finishes the camera visibly stutters; a linear glide
  /// composes smoothly with its successor. This enum exists in the engine
  /// abstraction specifically so that hard-won detail survives the port.
  linear,

  /// Ease in and out. For deliberate one-off flights — the cinematic
  /// entrance into guidance, or resuming after free-roam.
  eased,
}

/// The chase camera's framing while guiding.
///
/// Values ported from `updateNavCamera` in `src/globe.ts`.
const double kNavCameraBackMeters = 95;
const double kNavCameraUpMeters = 52;
const double kNavCameraPitchDegrees = -22;

/// The follow ("my location") camera's framing.
///
/// Values ported from `applyFollow` in `src/globe.ts`.
const double kFollowCameraBackMeters = 150;
const double kFollowCameraUpMeters = 75;
const double kFollowCameraPitchDegrees = -28;

/// What the camera should do in response to a GPS fix.
final class CameraCommand {
  const CameraCommand({
    required this.courseDegrees,
    required this.backMeters,
    required this.upMeters,
    required this.pitchDegrees,
    required this.duration,
    required this.curve,
  });

  final double courseDegrees;
  final double backMeters;
  final double upMeters;
  final double pitchDegrees;
  final Duration duration;
  final CameraCurve curve;
}

/// Centralises every camera timing rule the legacy app arrived at.
///
/// In the original these lived as separate `lastXAt` timestamps and inline
/// comparisons scattered through `globe.ts`, which is how the mobile
/// resolution-scale regression slipped in unnoticed. Gathering them here
/// makes the whole thermal policy inspectable in one place — and testable,
/// via an injectable clock.
final class CameraPolicy {
  CameraPolicy({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _followGate = MinInterval(kFollowReaimInterval, clock: clock),
      _heightGate = MinInterval(kHeightRefineInterval, clock: clock),
      _snapGate = MinInterval(kRouteSnapInterval, clock: clock);

  final DateTime Function() _clock;
  final MinInterval _followGate;
  final MinInterval _heightGate;
  final MinInterval _snapGate;

  bool _manualOverride = false;
  DateTime? _manualSince;
  double _lastCourseDegrees = 0;

  /// True while the user has taken manual control during guidance.
  bool get isManualOverride => _manualOverride;

  /// The most recent course, replayed when the chase camera resumes.
  double get lastCourseDegrees => _lastCourseDegrees;

  /// Whether the follow camera may re-aim now (consumes the slot).
  bool allowFollowReaim() => _followGate.tryFire();

  /// Whether surface height may be refined now (consumes the slot).
  bool allowHeightRefine() => _heightGate.tryFire();

  /// Whether the route may be re-snapped to the live position (consumes the
  /// slot).
  bool allowRouteSnap() => _snapGate.tryFire();

  /// Record a manual pan/zoom during guidance. Suspends the chase camera
  /// without ending navigation.
  void onManualInteraction() {
    _manualOverride = true;
    _manualSince = _clock();
  }

  /// Whether the chase camera should resume now, having been idle for
  /// [kNavResumeDelay]. Returns true exactly once per free-roam episode.
  bool shouldResumeAfterFreeRoam() {
    if (!_manualOverride) return false;
    final since = _manualSince;
    if (since == null) return false;
    if (_clock().difference(since) < kNavResumeDelay) return false;
    _manualOverride = false;
    _manualSince = null;
    return true;
  }

  /// Clear manual override immediately (e.g. guidance ended).
  void clearManualOverride() {
    _manualOverride = false;
    _manualSince = null;
  }

  /// Build the chase-camera command for a fix, or null while the user has
  /// manual control.
  ///
  /// `cinematic` selects the eased 1.2 s entrance used when guidance starts
  /// or resumes; the ordinary per-fix path is the 0.6 s **linear** glide.
  CameraCommand? navCameraFor(double courseDegrees, {bool cinematic = false}) {
    _lastCourseDegrees = courseDegrees;
    if (_manualOverride) return null;
    return CameraCommand(
      courseDegrees: courseDegrees,
      backMeters: kNavCameraBackMeters,
      upMeters: kNavCameraUpMeters,
      pitchDegrees: kNavCameraPitchDegrees,
      duration: cinematic ? kNavCameraCinematic : kNavCameraGlide,
      curve: cinematic ? CameraCurve.eased : CameraCurve.linear,
    );
  }

  /// Build the follow-mode command, or null if throttled.
  CameraCommand? followCameraFor(
    double headingDegrees, {
    bool instant = false,
  }) {
    if (!instant && !allowFollowReaim()) return null;
    return CameraCommand(
      courseDegrees: headingDegrees,
      backMeters: kFollowCameraBackMeters,
      upMeters: kFollowCameraUpMeters,
      pitchDegrees: kFollowCameraPitchDegrees,
      duration: instant ? Duration.zero : kNavCameraCinematic,
      curve: CameraCurve.eased,
    );
  }

  /// Reset every gate and override. Call when guidance starts or stops.
  void reset() {
    _followGate.reset();
    _heightGate.reset();
    _snapGate.reset();
    clearManualOverride();
  }
}
