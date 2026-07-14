import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_surface.dart';
import 'maneuver_icons.dart';

/// Full turn-by-turn HUD: instruction banner (top) + ETA panel (bottom).
/// Both are driven purely by [navigationSessionProvider]'s [NavProgress]
/// ticks, which is exactly the same state the CarPlay/Android Auto bridges
/// consume — this widget is just one more subscriber.
class NavigationInstructionBanner extends ConsumerWidget {
  const NavigationInstructionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(navigationSessionProvider);
    final units = ref.watch(unitSystemProvider);
    if (session == null) return const SizedBox.shrink();

    final progress = session.progress;
    final maneuvers = session.route.maneuvers;
    if (progress == null || maneuvers.isEmpty) return const SizedBox.shrink();

    final maneuver = maneuvers[progress.currentManeuverIndex.clamp(0, maneuvers.length - 1)];

    return GlassSurface(
      elevated: true,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(maneuverIconFor(maneuver.type), color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Formatters.distance(progress.distanceToManeuverMeters, units),
                  style: AppTypography.title2,
                ),
                Text(
                  maneuver.instruction,
                  style: AppTypography.callout.copyWith(color: context.glass.textTertiary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (progress.isOffRoute)
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(Icons.gps_off_rounded, color: AppColors.warning),
            ),
        ],
      ),
    );
  }
}

class NavigationEtaPanel extends ConsumerWidget {
  const NavigationEtaPanel({super.key, required this.onEnd});

  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(navigationSessionProvider);
    final units = ref.watch(unitSystemProvider);
    if (session == null) return const SizedBox.shrink();
    final progress = session.progress;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: GlassSurface(
          elevated: true,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: _EtaStat(
                  value: progress != null ? Formatters.etaClock(progress.eta) : '—',
                  label: 'ETA',
                ),
              ),
              Expanded(
                child: _EtaStat(
                  value: progress != null
                      ? Formatters.duration(Duration(seconds: progress.durationRemainingSeconds.round()))
                      : '—',
                  label: 'Time',
                ),
              ),
              Expanded(
                child: _EtaStat(
                  value: progress != null ? Formatters.distance(progress.distanceRemainingMeters, units) : '—',
                  label: 'Distance',
                ),
              ),
              FilledButton(
                onPressed: onEnd,
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger, shape: const CircleBorder(), padding: const EdgeInsets.all(14)),
                child: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EtaStat extends StatelessWidget {
  const _EtaStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTypography.title3),
        Text(label, style: AppTypography.caption1.copyWith(color: context.glass.textTertiary)),
      ],
    );
  }
}
