import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/glass_surface.dart';

/// The tappable search field that lives on the map — tapping opens the
/// full-screen [SearchOverlay]; this widget itself never opens a keyboard.
class MapSearchBarChip extends StatelessWidget {
  const MapSearchBarChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        elevated: true,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: context.glass.textTertiary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Search Phantom Eye',
                style: AppTypography.body.copyWith(color: context.glass.textTertiary),
              ),
            ),
            Icon(Icons.mic_rounded, color: context.glass.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
