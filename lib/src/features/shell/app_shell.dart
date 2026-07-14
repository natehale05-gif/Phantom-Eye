import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/routing_providers.dart';
import '../../state/track_recording_provider.dart';
import '../library/library_screen.dart';
import '../map/map_screen.dart';
import '../mesh/mesh_screen.dart';
import '../navigation/route_name_dialog.dart';
import '../search/search_overlay.dart';
import '../settings/settings_screen.dart';
import '../weather/weather_panel.dart';

/// Root tab shell: Map / Library / Mesh / Settings. The Map tab hosts its
/// own full-screen sub-navigation (search overlay, weather panel) pushed
/// via the root [Navigator] so they can cover the tab bar.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(trackRecordingProvider);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          MapScreen(
            onOpenSearch: () => _openSearch(context),
            onOpenWeather: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const WeatherPanel()),
            ),
            onOpenSettings: () => setState(() => _index = 3),
            onOpenMesh: () => setState(() => _index = 2),
            onOpenNavigation: () {},
          ),
          const LibraryScreen(),
          const MeshScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recording.status != RecordingStatus.idle) _RecordingBar(state: recording),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Map'),
              NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'Library'),
              NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Mesh'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
            ],
          ),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => SearchOverlay(
          onPlaceSelected: (place) {
            Navigator.of(context, rootNavigator: true).pop();
            ref.read(selectedPlaceProvider.notifier).set(place);
          },
        ),
      ),
    );
  }
}

class _RecordingBar extends ConsumerWidget {
  const _RecordingBar({required this.state});
  final TrackRecordingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Recording track — ${(state.distanceMeters / 1000).toStringAsFixed(2)} km',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () async {
                final name = await showRouteNameDialog(context, defaultName: 'Track ${DateTime.now().month}/${DateTime.now().day}');
                if (name != null) {
                  await ref.read(trackRecordingProvider.notifier).stopAndSave(name);
                }
              },
              child: const Text('Stop & Save'),
            ),
          ],
        ),
      ),
    );
  }
}
