import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/route_result.dart';
import '../../models/saved_route.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_surface.dart';
import '../navigation/route_name_dialog.dart';

/// Bottom panel for the custom route builder (orange waypoint-dots control):
/// Drive/Walk/Bike profile switch, live distance/elevation/time, undo/clear,
/// Save (into the Routes library) or Start (turn-by-turn on the custom route).
class RouteBuilderPanel extends ConsumerWidget {
  const RouteBuilderPanel({super.key, required this.onStart, required this.onClose});

  final void Function(SavedRoute route) onStart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builder = ref.watch(routeBuilderProvider);
    final units = ref.watch(unitSystemProvider);

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
                  Icon(Icons.share_location_rounded, color: AppColors.accentOffroad),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Route builder', style: AppTypography.headline),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
                ],
              ),
              Text(
                builder.waypoints.isEmpty
                    ? 'Tap the map to drop your first waypoint.'
                    : 'Tap the map to add more waypoints.',
                style: AppTypography.footnote.copyWith(color: context.glass.textTertiary),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final p in TravelProfile.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: GlassPill(
                        selected: builder.profile == p,
                        selectedColor: AppColors.accentOffroad,
                        onTap: () => ref.read(routeBuilderProvider.notifier).setProfile(p),
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
              if (builder.waypoints.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Stat(
                      icon: Icons.straighten_rounded,
                      label: Formatters.distance(builder.distanceMeters, units),
                    ),
                    _Stat(
                      icon: Icons.schedule_rounded,
                      label: builder.durationSeconds > 0
                          ? Formatters.duration(Duration(seconds: builder.durationSeconds.round()))
                          : '—',
                    ),
                    _Stat(
                      icon: Icons.trending_up_rounded,
                      label: Formatters.elevation(builder.elevationGainMeters, units),
                      color: AppColors.elevationGain,
                    ),
                    _Stat(
                      icon: Icons.trending_down_rounded,
                      label: Formatters.elevation(builder.elevationLossMeters, units),
                      color: AppColors.elevationLoss,
                    ),
                    if (builder.isLoading)
                      const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              if (builder.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(builder.error!, style: AppTypography.caption1.copyWith(color: AppColors.warning)),
                ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: builder.waypoints.isEmpty ? null : () => ref.read(routeBuilderProvider.notifier).undo(),
                    icon: const Icon(Icons.undo_rounded),
                    tooltip: 'Undo last waypoint',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filledTonal(
                    onPressed: builder.waypoints.isEmpty ? null : () => ref.read(routeBuilderProvider.notifier).clear(),
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Clear all',
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: builder.waypoints.length < 2
                        ? null
                        : () async {
                            final name = await showRouteNameDialog(context, defaultName: 'Custom route');
                            if (name == null) return;
                            final route = builder.snappedRoute;
                            final saved = route != null
                                ? SavedRoute.fromRouteResult(name, route)
                                : SavedRoute(
                                    name: name,
                                    path: builder.waypoints,
                                    profile: builder.profile,
                                    distanceMeters: builder.distanceMeters,
                                    durationSeconds: builder.durationSeconds,
                                    elevationGainMeters: builder.elevationGainMeters,
                                    elevationLossMeters: builder.elevationLossMeters,
                                  );
                            await ref.read(savedRoutesProvider.notifier).add(saved);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Saved "$name" to Routes')),
                              );
                            }
                          },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: builder.waypoints.length < 2
                        ? null
                        : () {
                            final route = builder.snappedRoute;
                            final saved = route != null
                                ? SavedRoute.fromRouteResult('Custom route', route)
                                : SavedRoute(
                                    name: 'Custom route',
                                    path: builder.waypoints,
                                    profile: builder.profile,
                                    distanceMeters: builder.distanceMeters,
                                    durationSeconds: builder.durationSeconds,
                                  );
                            onStart(saved);
                          },
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Start'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accentOffroad),
                  ),
                ],
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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.caption1),
      ],
    );
  }
}
