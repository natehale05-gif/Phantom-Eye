import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../meshtastic/meshtastic_ble_service.dart';
import '../../models/mesh_node.dart';
import '../../state/mesh_providers.dart';
import '../../theme/theme.dart';

/// Meshtastic tab: pair a radio over BLE, see connection status, and see
/// where your friends are (every other node's last known GPS position),
/// per the brief's "Meshtastic capabilities to see where your friends are".
class MeshScreen extends ConsumerWidget {
  const MeshScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(meshConnectionStateProvider).valueOrNull ?? MeshConnectionState.disconnected;
    final nodesAsync = ref.watch(meshNodesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching_rounded),
            tooltip: 'Pair a radio',
            onPressed: () => _showDevicePicker(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          _ConnectionBanner(state: connectionState),
          Expanded(
            child: nodesAsync.when(
              data: (nodes) {
                final friends = nodes.values.where((n) => !n.isSelf).toList()
                  ..sort((a, b) => (b.lastHeard ?? DateTime(0)).compareTo(a.lastHeard ?? DateTime(0)));
                if (friends.isEmpty) {
                  return _EmptyState(connected: connectionState == MeshConnectionState.ready);
                }
                return ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, i) => _FriendTile(node: friends[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Mesh error')),
            ),
          ),
        ],
      ),
    );
  }

  void _showDevicePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _DevicePickerSheet(),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.state});
  final MeshConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state) {
      MeshConnectionState.disconnected => (Icons.bluetooth_disabled_rounded, 'Not connected', Colors.grey),
      MeshConnectionState.connecting => (Icons.bluetooth_searching_rounded, 'Connecting…', AppColors.warning),
      MeshConnectionState.configuring => (Icons.sync_rounded, 'Downloading node database…', AppColors.warning),
      MeshConnectionState.ready => (Icons.bluetooth_connected_rounded, 'Connected', AppColors.success),
      MeshConnectionState.error => (Icons.error_outline_rounded, 'Connection error', AppColors.danger),
    };
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: context.glass.raised, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: AppTypography.callout),
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.node});
  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.meshColorForNodeNum(node.nodeNum);
    final initials = (node.shortName ?? node.displayName).trim();
    final avatarText = initials.isEmpty ? '?' : initials.substring(0, initials.length.clamp(0, 2)).toUpperCase();
    return ListTile(
      leading: CircleAvatar(backgroundColor: color, child: Text(avatarText)),
      title: Text(node.displayName),
      subtitle: Text(
        [
          if (node.point != null) '${node.point!.latitude.toStringAsFixed(4)}, ${node.point!.longitude.toStringAsFixed(4)}',
          if (node.batteryPercent != null) '🔋${node.batteryPercent}%',
          if (node.lastHeard != null) Formatters.relativeTime(node.lastHeard!, DateTime.now()),
        ].join(' · '),
      ),
      trailing: node.point == null ? const Icon(Icons.location_off_outlined, size: 18) : const Icon(Icons.location_on_rounded, size: 18),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_rounded, size: 48, color: context.glass.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              connected
                  ? 'No other nodes seen yet — friends will appear here as their radios come into range.'
                  : 'Pair a Meshtastic radio to see where your friends are, off-grid.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicePickerSheet extends ConsumerWidget {
  const _DevicePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanAsync = ref.watch(meshScanResultsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nearby Meshtastic radios', style: AppTypography.headline),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 300,
              child: scanAsync.when(
                data: (results) {
                  if (results.isEmpty) {
                    return const Center(child: Text('Scanning…'));
                  }
                  return ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final result = results[i];
                      return ListTile(
                        leading: const Icon(Icons.router_rounded),
                        title: Text(result.advertisementData.advName.isNotEmpty
                            ? result.advertisementData.advName
                            : result.device.remoteId.str),
                        subtitle: Text('RSSI ${result.rssi}'),
                        onTap: () async {
                          Navigator.of(context).pop();
                          try {
                            await ref.read(meshtasticBleServiceProvider).connect(result.device);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not connect: $e')),
                              );
                            }
                          }
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('Bluetooth scan failed. Check permissions.')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
