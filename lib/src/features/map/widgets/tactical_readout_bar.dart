import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../state/providers.dart';
import '../../../theme/theme.dart';
import '../../../widgets/glass_surface.dart';

/// A compact "tactical" readout strip — lat/lng, heading, speed, elevation —
/// styled after aviation/offroad HUDs. Purely informational chrome that
/// sits above the tab bar; expands slightly to show elevation when in
/// Offroad mode, since elevation matters a lot more off-pavement.
class TacticalReadoutBar extends ConsumerWidget {
  const TacticalReadoutBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionStreamProvider).valueOrNull;
    final units = ref.watch(unitSystemProvider);
    final mode = ref.watch(appModeProvider);

    if (position == null) {
      return const SizedBox.shrink();
    }

    final items = <_ReadoutItem>[
      _ReadoutItem('LAT', position.latitude.toStringAsFixed(5)),
      _ReadoutItem('LNG', position.longitude.toStringAsFixed(5)),
      _ReadoutItem(
        'HDG',
        position.heading >= 0
            ? '${position.heading.round()}° ${Formatters.compassDirection(position.heading)}'
            : '—',
      ),
      _ReadoutItem('SPD', position.speed >= 0 ? Formatters.speed(position.speed, units) : '—'),
      if (mode == AppMode.offroad)
        _ReadoutItem('ELV', Formatters.elevation(position.altitude, units)),
    ];

    return GlassSurface(
      elevated: true,
      borderRadius: BorderRadius.circular(AppRadius.md),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final item in items) _ReadoutColumn(item: item),
        ],
      ),
    );
  }
}

class _ReadoutItem {
  const _ReadoutItem(this.label, this.value);
  final String label;
  final String value;
}

class _ReadoutColumn extends StatelessWidget {
  const _ReadoutColumn({required this.item});
  final _ReadoutItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.label, style: AppTypography.caption2.copyWith(color: context.glass.textTertiary)),
        const SizedBox(height: 2),
        Text(item.value, style: AppTypography.subhead.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}
