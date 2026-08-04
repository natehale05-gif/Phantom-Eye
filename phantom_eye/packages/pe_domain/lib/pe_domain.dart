/// Pure-Dart domain logic for Phantom Eye.
///
/// Everything here is engine-agnostic and Flutter-free by design, enforced at
/// review time and (once the Flutter packages land) by a dependency lint.
/// This is where the accumulated, hard-won behaviour of the original
/// TypeScript app lives — the parts that took real debugging to get right and
/// that must not be casually re-derived:
///
///  * [RouteProjector] — windowed projection, so a long route is not
///    rescanned on every GPS fix.
///  * [OffRouteDetector] — sustained-deviation confirmation, cooldown and
///    in-flight guarding, so noise does not trigger reroutes.
///  * [RouteSnapper] — the route bends to you, not the other way around.
///  * [CameraPolicy] — the throttles that were the phone-overheating fix,
///    plus the linear-glide detail that keeps the chase camera from
///    stuttering between fixes.
library;

export 'src/camera/camera_policy.dart';
export 'src/field/track_recorder.dart';
export 'src/field/waypoint_store.dart';
export 'src/field/waypoint_styles.dart';
export 'src/navigation/off_route_detector.dart';
export 'src/offline/download_area_planner.dart';
export 'src/places/categories.dart';
export 'src/places/curated_places.dart';
export 'src/places/gas_prices.dart';
export 'src/places/nearby.dart';
export 'src/places/opening_hours.dart';
export 'src/places/recent_places.dart';
export 'src/navigation/route_projector.dart';
export 'src/navigation/route_snapper.dart';
export 'src/settings/layer_settings.dart';
export 'src/trails/trail_layers.dart';
export 'src/weather/weather_codes.dart';
