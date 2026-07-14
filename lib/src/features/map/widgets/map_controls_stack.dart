import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import '../../../theme/theme.dart';
import '../../../widgets/glass_surface.dart';

/// Right-edge vertical stack of map controls: recenter-on-me, cycle base
/// style (streets/satellite/topo), toggle hillshade, enter the custom
/// route-builder ("orange waypoint-dots" control per the brief), and open
/// the Meshtastic friends layer.
class MapControlsStack extends ConsumerWidget {
  const MapControlsStack({
    super.key,
    required this.onLocateMe,
    required this.onOpenMesh,
    required this.onToggleRouteBuilder,
  });

  final VoidCallback onLocateMe;
  final VoidCallback onOpenMesh;
  final VoidCallback onToggleRouteBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(mapBaseStyleProvider);
    final routeBuilderActive = ref.watch(routeBuilderProvider).isActive;
    final meshNodes = ref.watch(meshNodesProvider).valueOrNull ?? const {};
    final friendCount = meshNodes.values.where((n) => !n.isSelf && n.point != null).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassIconButton(
          icon: Icons.my_location_rounded,
          onTap: onLocateMe,
          tooltip: 'Locate me',
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassIconButton(
          icon: switch (style) {
            MapBaseStyle.streets => Icons.map_rounded,
            MapBaseStyle.satellite => Icons.satellite_alt_rounded,
            MapBaseStyle.topo => Icons.terrain_rounded,
          },
          onTap: () => ref.read(mapBaseStyleProvider.notifier).cycle(),
          tooltip: 'Map style: ${style.label}',
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassIconButton(
          icon: Icons.share_location_rounded,
          onTap: onToggleRouteBuilder,
          active: routeBuilderActive,
          activeColor: AppColors.accentOffroad,
          tooltip: 'Build a route',
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassIconButton(
          icon: Icons.satellite_alt_outlined,
          onTap: onOpenMesh,
          badge: friendCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '$friendCount',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                )
              : null,
          tooltip: 'Mesh friends',
        ),
      ],
    );
  }
}
