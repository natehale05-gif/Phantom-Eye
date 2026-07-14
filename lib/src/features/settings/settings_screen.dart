import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/unit_system.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    final mode = ref.watch(appModeProvider);
    final hillshade = ref.watch(hillshadeOverlayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('General'),
          SwitchListTile(
            title: const Text('Imperial units'),
            subtitle: const Text('Miles, feet, °F, mph'),
            value: units.isImperial,
            onChanged: (_) => ref.read(unitSystemProvider.notifier).toggle(),
          ),
          SwitchListTile(
            title: const Text('Offroad mode'),
            subtitle: const Text('Switches accent color + default map style to Topo'),
            value: mode == AppMode.offroad,
            onChanged: (_) => ref.read(appModeProvider.notifier).toggle(),
          ),
          SwitchListTile(
            title: const Text('Hillshade overlay'),
            subtitle: const Text('Terrain relief shading on Satellite/Topo'),
            value: hillshade,
            onChanged: (_) => ref.read(hillshadeOverlayProvider.notifier).toggle(),
          ),
          const _SectionHeader('Land data'),
          const ListTile(
            leading: Icon(Icons.map_outlined),
            title: Text('Land ownership boundaries'),
            subtitle: Text(
              'Not available yet — requires a licensed GIS data source (e.g. BLM/USFS '
              'parcel feeds). See README for integration notes.',
            ),
            enabled: false,
          ),
          const ListTile(
            leading: Icon(Icons.pets_outlined),
            title: Text('Hunting units'),
            subtitle: Text('Not available yet — requires state game-department GIS feeds.'),
            enabled: false,
          ),
          const _SectionHeader('Data & Import'),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Import GPX'),
            subtitle: const Text('Bring in tracks, routes, or waypoints from another app'),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hook up a file picker (file_selector/file_picker) to enable this.')),
            ),
          ),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Third-party services'),
            subtitle: Text(
              'Photon (geocoding), Valhalla + OSRM (routing), Open-Meteo (weather/elevation), '
              'OpenStreetMap/OpenTopoMap/Esri (map tiles). All public demo endpoints — see README '
              'before shipping.',
            ),
          ),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: const Text('Phantom Eye'),
                subtitle: Text(info == null ? '…' : 'v${info.version} (${info.buildNumber})'),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Text(title, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
