/// Metres off-route before deviation is even considered.
///
/// Ported from `OFF_ROUTE_METERS` in `src/navigation.ts:22`.
const double kOffRouteMeters = 55;

/// How long deviation must be sustained before it counts.
///
/// Ported from `OFF_ROUTE_CONFIRM_MS` in `src/navigation.ts:23`. This is the
/// difference between "you actually turned off" and "one noisy fix bounced
/// you into a parking lot" — without it, a single bad reading triggers a
/// spurious reroute mid-drive.
const Duration kOffRouteConfirm = Duration(milliseconds: 3000);

/// Minimum spacing between reroute attempts.
///
/// Ported from the `Date.now() - this.lastReroute < 5000` guard in
/// `src/navigation.ts:274`.
const Duration kRerouteCooldown = Duration(seconds: 5);

/// Decides when a sustained deviation warrants a reroute.
///
/// This is a faithful port of the logic spread across `Navigator.advance`
/// and `Navigator.reroute` in `src/navigation.ts`, pulled into one testable
/// object. It deliberately keeps all four guards the original accumulated:
///
///  1. a distance threshold ([kOffRouteMeters]),
///  2. a sustain window ([kOffRouteConfirm]) that resets the moment you come
///     back on route, so each deviation episode is timed independently,
///  3. a cooldown ([kRerouteCooldown]) so a persistent deviation cannot spam
///     the routing service, and
///  4. an in-flight guard, so a slow routing response cannot overlap itself.
///
/// Arrival suppresses everything — near the destination you are legitimately
/// off the road geometry, and rerouting there is never right.
final class OffRouteDetector {
  OffRouteDetector({
    this.offRouteMeters = kOffRouteMeters,
    this.confirmAfter = kOffRouteConfirm,
    this.cooldown = kRerouteCooldown,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final double offRouteMeters;
  final Duration confirmAfter;
  final Duration cooldown;
  final DateTime Function() _clock;

  DateTime? _offRouteSince;
  DateTime? _lastReroute;
  bool _rerouteInFlight = false;

  /// Whether a reroute request is currently outstanding.
  bool get isRerouting => _rerouteInFlight;

  /// Whether the current position is being counted as off-route right now
  /// (may not yet have been sustained long enough to trigger).
  bool get isOffRoute => _offRouteSince != null;

  /// Feed in the latest projection offset.
  ///
  /// Returns true when the caller should start a reroute. Never returns true
  /// while one is in flight, within the cooldown, or after arrival.
  bool update({required double offsetMeters, required bool arrived}) {
    if (arrived || offsetMeters <= offRouteMeters) {
      _offRouteSince = null;
      return false;
    }

    final now = _clock();
    _offRouteSince ??= now;

    if (now.difference(_offRouteSince!) < confirmAfter) return false;
    if (_rerouteInFlight) return false;

    final last = _lastReroute;
    if (last != null && now.difference(last) < cooldown) return false;

    return true;
  }

  /// Mark a reroute as started. Call this when acting on a true [update].
  void beginReroute() {
    _rerouteInFlight = true;
    _lastReroute = _clock();
  }

  /// Mark the in-flight reroute as finished, successfully or not.
  ///
  /// On success the caller should also [reset] — the deviation episode is
  /// over because the route itself changed.
  void endReroute() => _rerouteInFlight = false;

  /// Clear deviation tracking. Call after a successful reroute, and whenever
  /// guidance starts or stops.
  void reset() {
    _offRouteSince = null;
    _rerouteInFlight = false;
  }
}
