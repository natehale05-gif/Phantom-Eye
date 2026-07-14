import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../state/providers.dart';
import '../../../theme/theme.dart';
import '../../../widgets/glass_surface.dart';
import '../../weather/weather_icons.dart';

/// Live weather chip: fetches current conditions for the map's center,
/// refreshing as the user pans (the focus point is pushed in by
/// `map_screen.dart` on camera idle). Tapping opens the full forecast panel.
class MapWeatherChip extends ConsumerWidget {
  const MapWeatherChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(weatherSnapshotProvider);
    final units = ref.watch(unitSystemProvider);

    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        elevated: true,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: snapshotAsync.when(
          data: (snapshot) {
            if (snapshot == null) {
              return const SizedBox(width: 20, height: 20, child: Icon(Icons.location_searching, size: 16));
            }
            final current = snapshot.current;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  weatherIconFor(current.condition, isDay: current.isDay),
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  Formatters.temperature(current.temperatureC, units),
                  style: AppTypography.callout.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            );
          },
          loading: () => const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => Icon(Icons.cloud_off_rounded, size: 18, color: context.glass.textTertiary),
        ),
      ),
    );
  }
}
