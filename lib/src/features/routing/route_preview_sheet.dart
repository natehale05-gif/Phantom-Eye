import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/route_result.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_surface.dart';
import 'elevation_profile_chart.dart';

/// Full route preview: profile switch, distance/ETA summary, elevation
/// profile, and Start — shown once a place card's "Directions" is tapped.
class RoutePreviewSheet extends ConsumerWidget {
  const RoutePreviewSheet({super.key, required this.onStart, required this.onDismiss});

  final void Function(RouteResult route) onStart;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeAsync = ref.watch(previewRouteProvider);
    final elevationAsync = ref.watch(previewElevationProvider);
    final profile = ref.watch(travelProfileProvider);
    final units = ref.watch(unitSystemProvider);
    final place = ref.watch(selectedPlaceProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: GlassSurface(
          elevated: true,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      place?.name ?? 'Route preview',
                      style: AppTypography.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(onPressed: onDismiss, icon: const Icon(Icons.close_rounded)),
                ],
              ),
              Row(
                children: [
                  for (final p in TravelProfile.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: GlassPill(
                        selected: profile == p,
                        onTap: () => ref.read(travelProfileProvider.notifier).set(p),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_profileIcon(p), size: 14),
                            const SizedBox(width: 4),
                            Text(p.label, style: AppTypography.caption1),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              routeAsync.when(
                data: (route) {
                  if (route == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Formatters.duration(Duration(seconds: route.durationSeconds.round())),
                              style: AppTypography.title2),
                          const SizedBox(width: AppSpacing.sm),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '· ${Formatters.distance(route.distanceMeters, units)} · ${Formatters.etaClock(DateTime.now().add(Duration(seconds: route.durationSeconds.round())))}',
                              style: AppTypography.callout.copyWith(color: context.glass.textTertiary),
                            ),
                          ),
                        ],
                      ),
                      if (route.source != RouteSource.valhalla)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            route.source == RouteSource.osrm
                                ? 'via OSRM fallback'
                                : 'straight-line estimate — no live route data',
                            style: AppTypography.caption1.copyWith(color: AppColors.warning),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      elevationAsync.when(
                        data: (elevation) {
                          if (elevation == null) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ElevationProfileChart(profile: elevation.profile, units: units),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  _ElevationStat(
                                    icon: Icons.trending_up_rounded,
                                    color: AppColors.elevationGain,
                                    label: Formatters.elevation(elevation.gainMeters, units),
                                  ),
                                  const SizedBox(width: AppSpacing.lg),
                                  _ElevationStat(
                                    icon: Icons.trending_down_rounded,
                                    color: AppColors.elevationLoss,
                                    label: Formatters.elevation(elevation.lossMeters, units),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                          child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => onStart(route),
                          icon: const Icon(Icons.navigation_rounded),
                          label: const Text('Start'),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text('Could not calculate a route.', style: AppTypography.body.copyWith(color: AppColors.danger)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _profileIcon(TravelProfile p) => switch (p) {
        TravelProfile.drive => Icons.directions_car_filled_rounded,
        TravelProfile.walk => Icons.directions_walk_rounded,
        TravelProfile.bike => Icons.directions_bike_rounded,
      };
}

class _ElevationStat extends StatelessWidget {
  const _ElevationStat({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.callout),
      ],
    );
  }
}
