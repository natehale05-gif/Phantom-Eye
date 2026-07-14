import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../models/geo_point.dart';
import '../../models/place.dart';
import '../../models/route_result.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../navigation/navigation_overlay.dart';
import '../place/place_card.dart';
import '../route_builder/route_builder_panel.dart';
import '../routing/route_preview_sheet.dart';
import 'geo_conversions.dart';
import 'map_styles.dart';
import 'phantom_map_controller.dart';
import 'widgets/map_controls_stack.dart';
import 'widgets/search_bar_chip.dart';
import 'widgets/status_bar.dart';
import 'widgets/tactical_readout_bar.dart';
import 'widgets/weather_chip.dart';

/// The map shell: hosts the MapLibre view and every native-Flutter chrome
/// widget floating over it (status bar, search bar, weather chip, controls,
/// tactical readout, and whichever bottom sheet is currently relevant).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenWeather,
    required this.onOpenSettings,
    required this.onOpenMesh,
    required this.onOpenNavigation,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMesh;
  final VoidCallback onOpenNavigation;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  PhantomMapController? _map;
  bool _styleLoaded = false;

  static const _defaultCamera = CameraPosition(target: LatLng(39.5, -98.35), zoom: 4.2);

  @override
  Widget build(BuildContext context) {
    final baseStyle = ref.watch(mapBaseStyleProvider);
    final hillshade = ref.watch(hillshadeOverlayProvider);

    // Keep map annotation layers in sync with app state without rebuilding
    // the MapLibreMap widget itself (which would flash/reset the camera).
    ref.listen(routeBuilderProvider, (prev, next) {
      _map?.setRouteBuilderWaypoints(next.waypoints);
      if (!next.isActive && (prev?.isActive ?? false)) {
        _map?.setRouteBuilderWaypoints(const []);
      }
    });
    ref.listen(previewRouteProvider, (prev, next) {
      final route = next.valueOrNull;
      if (route != null) {
        _map?.setRouteLine(route.path);
        _map?.fitBounds(route.path);
      } else if (next is! AsyncLoading) {
        _map?.clearRouteLine();
      }
    });
    ref.listen(waypointsProvider, (prev, next) {
      final list = next.valueOrNull;
      if (list != null) _map?.setWaypoints(list);
    });
    ref.listen(meshNodesProvider, (prev, next) {
      final nodes = next.valueOrNull;
      if (nodes != null) _map?.setMeshNodes(nodes.values);
    });
    ref.listen(selectedPlaceProvider, (prev, next) {
      _map?.setPlacePin(next);
      if (next != null) _map?.flyTo(next.point);
    });
    ref.listen(navigationSessionProvider, (prev, next) {
      if (next != null && next.route.path.isNotEmpty) {
        _map?.setRouteLine(next.route.path, color: AppColors.accentEveryday);
      } else if (next == null) {
        _map?.clearRouteLine();
      }
    });

    final navSession = ref.watch(navigationSessionProvider);
    final routeBuilder = ref.watch(routeBuilderProvider);
    final selectedPlace = ref.watch(selectedPlaceProvider);
    final hasPreviewRoute = ref.watch(routeRequestProvider) != null;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              initialCameraPosition: _defaultCamera,
              styleString: MapStyles.styleJsonFor(baseStyle, hillshade: hillshade),
              myLocationEnabled: true,
              myLocationTrackingMode: MyLocationTrackingMode.none,
              trackCameraPosition: true,
              compassEnabled: true,
              logoEnabled: false,
              onMapCreated: (controller) {
                _map = PhantomMapController(controller);
              },
              onStyleLoadedCallback: () {
                setState(() => _styleLoaded = true);
                _centerOnUserIfAvailable();
              },
              onCameraIdle: () {
                final pos = _map?.controller.cameraPosition;
                if (pos != null) {
                  ref.read(weatherFocusProvider.notifier).update(pos.target.toGeoPoint());
                }
              },
              onMapClick: (point, latLng) => _handleMapTap(latLng.toGeoPoint()),
            ),
          ),
          if (!_styleLoaded) const Positioned.fill(child: ColoredBox(color: Color(0xFF0D0F14))),

          // --- Top chrome ---
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  children: [
                    MapStatusBar(onSettingsTap: widget.onOpenSettings),
                    if (navSession == null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        child: Row(
                          children: [
                            Expanded(child: MapSearchBarChip(onTap: widget.onOpenSearch)),
                            const SizedBox(width: AppSpacing.sm),
                            MapWeatherChip(onTap: widget.onOpenWeather),
                          ],
                        ),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        child: NavigationInstructionBanner(),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // --- Right control stack ---
          if (navSession == null)
            Positioned(
              right: AppSpacing.lg,
              top: 0,
              bottom: 0,
              child: Center(
                child: MapControlsStack(
                  onLocateMe: _centerOnUserIfAvailable,
                  onOpenMesh: widget.onOpenMesh,
                  onToggleRouteBuilder: _toggleRouteBuilder,
                ),
              ),
            ),

          // --- Bottom chrome ---
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomChrome(navSession, routeBuilder, selectedPlace, hasPreviewRoute),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomChrome(
    ActiveNavigationState? navSession,
    RouteBuilderState routeBuilder,
    Place? selectedPlace,
    bool hasPreviewRoute,
  ) {
    if (navSession != null) {
      return NavigationEtaPanel(onEnd: () => ref.read(navigationSessionProvider.notifier).stop());
    }
    if (routeBuilder.isActive) {
      return RouteBuilderPanel(
        onStart: (savedRoute) {
          final builderState = ref.read(routeBuilderProvider);
          final routeResult = builderState.snappedRoute ??
              RouteResult(
                profile: builderState.profile,
                source: RouteSource.straightLine,
                path: builderState.waypoints,
                maneuvers: [
                  RouteManeuver(
                    type: ManeuverType.depart,
                    instruction: 'Follow your custom route',
                    point: builderState.waypoints.first,
                    distanceMeters: builderState.distanceMeters,
                  ),
                  RouteManeuver(
                    type: ManeuverType.arrive,
                    instruction: 'Arrive at end of route',
                    point: builderState.waypoints.last,
                    distanceMeters: 0,
                  ),
                ],
                distanceMeters: builderState.distanceMeters,
                durationSeconds: builderState.durationSeconds,
              );
          ref.read(navigationSessionProvider.notifier).start(routeResult, simulate: true);
          ref.read(routeBuilderProvider.notifier).exitBuildMode();
          widget.onOpenNavigation();
        },
        onClose: () => ref.read(routeBuilderProvider.notifier).exitBuildMode(),
      );
    }
    if (hasPreviewRoute) {
      return RoutePreviewSheet(
        onStart: (route) {
          ref.read(navigationSessionProvider.notifier).start(route, simulate: true);
          ref.read(routeRequestProvider.notifier).clear();
          widget.onOpenNavigation();
        },
        onDismiss: () {
          ref.read(routeRequestProvider.notifier).clear();
          ref.read(selectedPlaceProvider.notifier).clear();
        },
      );
    }
    if (selectedPlace != null) {
      return PlaceCard(
        place: selectedPlace,
        onDirections: () {
          final origin = ref.read(currentGeoPointProvider);
          if (origin == null) return;
          ref.read(routeRequestProvider.notifier).request([origin, selectedPlace.point]);
        },
        onDismiss: () => ref.read(selectedPlaceProvider.notifier).clear(),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: const TacticalReadoutBar(),
    );
  }

  void _toggleRouteBuilder() {
    final notifier = ref.read(routeBuilderProvider.notifier);
    if (ref.read(routeBuilderProvider).isActive) {
      notifier.exitBuildMode();
    } else {
      ref.read(selectedPlaceProvider.notifier).clear();
      ref.read(routeRequestProvider.notifier).clear();
      notifier.enterBuildMode();
    }
  }

  Future<void> _handleMapTap(GeoPoint point) async {
    if (ref.read(routeBuilderProvider).isActive) {
      await ref.read(routeBuilderProvider.notifier).addWaypoint(point);
      return;
    }
    if (ref.read(navigationSessionProvider) != null) return;

    // Optimistically show a generic pin immediately, then refine with
    // reverse geocoding once it resolves.
    ref.read(selectedPlaceProvider.notifier).set(Place(name: 'Dropped pin', point: point));
    try {
      final place = await ref.read(geocodingServiceProvider).reverse(point);
      if (place != null) {
        ref.read(selectedPlaceProvider.notifier).set(place);
      }
    } catch (_) {
      // Keep the generic pin — reverse geocoding is best-effort.
    }
  }

  void _centerOnUserIfAvailable() {
    final point = ref.read(currentGeoPointProvider);
    if (point != null) {
      _map?.flyTo(point, zoom: 15);
    }
  }
}
