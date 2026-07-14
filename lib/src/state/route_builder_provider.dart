import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/geo_point.dart';
import '../models/route_result.dart';
import 'core_providers.dart';

/// Custom route builder ("orange waypoint-dots" control): tapping the map
/// in build mode drops a numbered waypoint; each new waypoint re-requests a
/// trail/road-snapped route through all dropped points so far (Valhalla,
/// straight-line fallback), and the panel tracks live distance/elevation/ETA.
class RouteBuilderState {
  const RouteBuilderState({
    this.isActive = false,
    this.waypoints = const [],
    this.profile = TravelProfile.walk,
    this.snappedRoute,
    this.isLoading = false,
    this.elevationGainMeters = 0,
    this.elevationLossMeters = 0,
    this.error,
  });

  final bool isActive;
  final List<GeoPoint> waypoints;
  final TravelProfile profile;
  final RouteResult? snappedRoute;
  final bool isLoading;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final String? error;

  double get distanceMeters => snappedRoute?.distanceMeters ?? GeoMath.pathLengthMeters(waypoints);
  double get durationSeconds => snappedRoute?.durationSeconds ?? 0;

  RouteBuilderState copyWith({
    bool? isActive,
    List<GeoPoint>? waypoints,
    TravelProfile? profile,
    RouteResult? snappedRoute,
    bool clearSnappedRoute = false,
    bool? isLoading,
    double? elevationGainMeters,
    double? elevationLossMeters,
    String? error,
    bool clearError = false,
  }) {
    return RouteBuilderState(
      isActive: isActive ?? this.isActive,
      waypoints: waypoints ?? this.waypoints,
      profile: profile ?? this.profile,
      snappedRoute: clearSnappedRoute ? null : (snappedRoute ?? this.snappedRoute),
      isLoading: isLoading ?? this.isLoading,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      elevationLossMeters: elevationLossMeters ?? this.elevationLossMeters,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class RouteBuilderNotifier extends Notifier<RouteBuilderState> {
  @override
  RouteBuilderState build() => const RouteBuilderState();

  void enterBuildMode() => state = state.copyWith(isActive: true);

  void exitBuildMode() => state = const RouteBuilderState();

  void setProfile(TravelProfile profile) {
    state = state.copyWith(profile: profile);
    _resnap();
  }

  Future<void> addWaypoint(GeoPoint point) async {
    state = state.copyWith(waypoints: [...state.waypoints, point], clearError: true);
    await _resnap();
  }

  void undo() {
    if (state.waypoints.isEmpty) return;
    final updated = [...state.waypoints]..removeLast();
    state = state.copyWith(waypoints: updated, clearSnappedRoute: true, clearError: true);
    _resnap();
  }

  void clear() {
    state = state.copyWith(waypoints: [], clearSnappedRoute: true, clearError: true);
  }

  Future<void> _resnap() async {
    if (state.waypoints.length < 2) {
      state = state.copyWith(clearSnappedRoute: true);
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = ref.read(routingServiceProvider);
      final route = await service.route(state.waypoints, state.profile);
      final elevationService = ref.read(elevationServiceProvider);
      final elevation = await elevationService.profileFor(route.path);
      state = state.copyWith(
        snappedRoute: route.copyWith(elevationProfile: elevation.profile),
        isLoading: false,
        elevationGainMeters: elevation.gainMeters,
        elevationLossMeters: elevation.lossMeters,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Could not snap route — showing straight line.');
    }
  }
}

final routeBuilderProvider = NotifierProvider<RouteBuilderNotifier, RouteBuilderState>(RouteBuilderNotifier.new);
