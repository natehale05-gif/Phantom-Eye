import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/geo_point.dart';
import '../models/unit_system.dart';
import '../models/weather.dart';
import 'core_providers.dart';
import 'settings_providers.dart';

/// The map center the weather chip is currently tracking. Updated as the
/// user pans (see `map_screen.dart`), which is what makes the weather chip
/// "live" per the brief — it reflects wherever's under the crosshair, not
/// just the user's GPS fix.
class WeatherFocusNotifier extends Notifier<GeoPoint?> {
  @override
  GeoPoint? build() => null;

  void update(GeoPoint point) {
    // Re-fetching on every pixel of pan would hammer the API; snap to a
    // coarse-ish grid (~1km) so panning locally doesn't retrigger fetches.
    final snapped = GeoPoint(
      (point.latitude * 100).round() / 100,
      (point.longitude * 100).round() / 100,
    );
    if (state == snapped) return;
    state = snapped;
  }
}

final weatherFocusProvider = NotifierProvider<WeatherFocusNotifier, GeoPoint?>(WeatherFocusNotifier.new);

final weatherSnapshotProvider = FutureProvider.autoDispose<WeatherSnapshot?>((ref) async {
  final focus = ref.watch(weatherFocusProvider);
  if (focus == null) return null;

  // Debounce: if the map keeps panning, wait for it to settle before
  // spending an API call — cheap to do with autoDispose + a delay, since
  // Riverpod cancels this future entirely if [focus] changes again before
  // the delay elapses (the provider gets re-created and this closure is
  // simply abandoned).
  await Future<void>.delayed(const Duration(milliseconds: 500));

  final service = ref.read(weatherServiceProvider);
  return service.fetch(focus);
});

final weatherUnitSystemProvider = Provider<UnitSystem>((ref) => ref.watch(unitSystemProvider));
