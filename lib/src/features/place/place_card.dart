import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/geo_point.dart';
import '../../models/place.dart';
import '../../models/route_result.dart';
import '../../models/waypoint.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_surface.dart';
import 'place_icons.dart';

/// Bottom sheet shown when a place is selected (search result tap, map
/// long-press, or a saved waypoint) — profile switch + quick distance/ETA
/// preview, "Directions" promotes it to the full route preview sheet.
class PlaceCard extends ConsumerWidget {
  const PlaceCard({super.key, required this.place, required this.onDirections, required this.onDismiss});

  final Place place;
  final VoidCallback onDirections;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(travelProfileProvider);
    final origin = ref.watch(currentGeoPointProvider);
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(placeIconFor(place.category), color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(place.name, style: AppTypography.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (place.subtitle != null)
                          Text(
                            place.subtitle!,
                            style: AppTypography.footnote.copyWith(color: context.glass.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: onDismiss, icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (origin != null)
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
                    const Spacer(),
                    Text(
                      Formatters.distance(GeoMath.distanceMeters(origin, place.point), units),
                      style: AppTypography.footnote.copyWith(color: context.glass.textTertiary),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await ref.read(waypointsProvider.notifier).add(
                              Waypoint(name: place.name, point: place.point),
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Saved "${place.name}"')),
                          );
                        }
                      },
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onDirections,
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Directions'),
                    ),
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
