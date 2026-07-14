import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/geo_point.dart';
import '../models/place.dart';
import '../models/route_result.dart';
import 'core_providers.dart';

class TravelProfileNotifier extends Notifier<TravelProfile> {
  @override
  TravelProfile build() => TravelProfile.drive;
  void set(TravelProfile value) => state = value;
}

final travelProfileProvider = NotifierProvider<TravelProfileNotifier, TravelProfile>(TravelProfileNotifier.new);

/// The place currently shown on the place card / route preview sheet.
class SelectedPlaceNotifier extends Notifier<Place?> {
  @override
  Place? build() => null;
  void set(Place? place) => state = place;
  void clear() => state = null;
}

final selectedPlaceProvider = NotifierProvider<SelectedPlaceNotifier, Place?>(SelectedPlaceNotifier.new);

/// A→B route preview request: origin + destination (+ optional
/// waypoints), recomputed whenever the profile changes. `null` when no
/// route is being previewed.
class RouteRequest {
  const RouteRequest({required this.stops, required this.profile});
  final List<GeoPoint> stops;
  final TravelProfile profile;
}

class RouteRequestNotifier extends Notifier<RouteRequest?> {
  @override
  RouteRequest? build() => null;

  void request(List<GeoPoint> stops) {
    state = RouteRequest(stops: stops, profile: ref.read(travelProfileProvider));
  }

  void clear() => state = null;
}

final routeRequestProvider = NotifierProvider<RouteRequestNotifier, RouteRequest?>(RouteRequestNotifier.new);

final previewRouteProvider = FutureProvider.autoDispose<RouteResult?>((ref) async {
  final request = ref.watch(routeRequestProvider);
  if (request == null || request.stops.length < 2) return null;
  final service = ref.read(routingServiceProvider);
  return service.route(request.stops, request.profile);
});

/// Elevation profile for whatever route is currently previewed — kept as a
/// separate provider so the (slower) elevation API call doesn't block the
/// route line from appearing immediately.
final previewElevationProvider = FutureProvider.autoDispose<
    ({List<ElevationPoint> profile, double gainMeters, double lossMeters})?>((ref) async {
  final route = await ref.watch(previewRouteProvider.future);
  if (route == null || route.path.length < 2) return null;
  final elevation = ref.read(elevationServiceProvider);
  return elevation.profileFor(route.path);
});
