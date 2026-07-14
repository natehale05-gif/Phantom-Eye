import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../../theme/theme.dart';
import '../../../widgets/glass_surface.dart';

/// Top overlay row: app mode switch (Everyday / Offroad) on the left,
/// settings entry on the right. Sits above the safe area, floating over
/// the map like the prototype's status/mode bar.
class MapStatusBar extends ConsumerWidget {
  const MapStatusBar({super.key, required this.onSettingsTap});

  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          GlassSurface(
            elevated: true,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeSegment(
                  label: 'Everyday',
                  icon: Icons.map_rounded,
                  selected: mode == AppMode.everyday,
                  color: AppColors.accentEveryday,
                  onTap: () => ref.read(appModeProvider.notifier).set(AppMode.everyday),
                ),
                _ModeSegment(
                  label: 'Offroad',
                  icon: Icons.terrain_rounded,
                  selected: mode == AppMode.offroad,
                  color: AppColors.accentOffroad,
                  onTap: () => ref.read(appModeProvider.notifier).set(AppMode.offroad),
                ),
              ],
            ),
          ),
          const Spacer(),
          GlassIconButton(icon: Icons.settings_rounded, onTap: onSettingsTap, tooltip: 'Settings'),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : context.glass.textTertiary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.footnote.copyWith(
                color: selected ? Colors.white : context.glass.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
