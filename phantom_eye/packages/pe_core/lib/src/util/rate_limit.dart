/// A minimum-interval gate.
///
/// This is the single most load-bearing utility in the port: the legacy app's
/// phone-overheating fix was ultimately a set of these guarding work that was
/// running on every GPS fix (follow-camera re-aim at 800 ms, surface-height
/// refinement at 400 ms, route re-snapping at 250 ms). Each one existed as
/// hand-rolled `performance.now() - lastX >= INTERVAL` scattered across
/// `globe.ts`; centralising it makes the policy visible and testable.
///
/// The clock is injectable so tests can drive it deterministically rather
/// than sleeping.
final class MinInterval {
  MinInterval(this.interval, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Duration interval;
  final DateTime Function() _clock;
  DateTime? _lastFired;

  /// Whether [tryFire] would succeed right now, without consuming the slot.
  bool get isReady {
    final last = _lastFired;
    if (last == null) return true;
    return _clock().difference(last) >= interval;
  }

  /// Consume the slot if the interval has elapsed. Returns whether the caller
  /// should proceed. The first call always succeeds.
  bool tryFire() {
    final now = _clock();
    final last = _lastFired;
    if (last != null && now.difference(last) < interval) return false;
    _lastFired = now;
    return true;
  }

  /// Forget the last fire, so the next [tryFire] succeeds immediately.
  void reset() => _lastFired = null;
}

/// Monotonically increasing generation counter for cancelling superseded
/// async work.
///
/// The legacy code spelled this as ad-hoc `const current = ++this.token; …
/// if (current !== this.token) return;` in at least six places
/// (`streetlabels.ts`, `trails.ts`, `globe.ts` route clamping, the search
/// controller). Naming it makes the intent explicit at each call site.
final class GenerationToken {
  int _current = 0;

  /// Start a new generation, invalidating all previous ones.
  int begin() => ++_current;

  /// Whether `generation` is still the newest one issued.
  bool isCurrent(int generation) => generation == _current;

  /// Invalidate everything outstanding without issuing a new generation.
  void invalidate() => _current++;
}
