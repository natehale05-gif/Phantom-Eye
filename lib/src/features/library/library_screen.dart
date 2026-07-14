import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/place.dart' show PlaceCategory;
import '../../models/route_result.dart';
import '../../models/saved_route.dart';
import '../../models/unit_system.dart';
import '../../models/waypoint.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../place/place_icons.dart';

/// "Library" tab: saved Routes, recorded Tracks, and Waypoints — the
/// onX/Gaia-style catalog of everything the user has planned or recorded.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() => _tabIndex = _tabController.index));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Routes'), Tab(text: 'Tracks'), Tab(text: 'Waypoints')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_RoutesTab(), _TracksTab(), _WaypointsTab()],
      ),
      floatingActionButton: _tabIndex == 1 ? const _RecordTrackFab() : null,
    );
  }
}

class _RecordTrackFab extends ConsumerWidget {
  const _RecordTrackFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(trackRecordingProvider);
    if (recording.status != RecordingStatus.idle) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      onPressed: () => ref.read(trackRecordingProvider.notifier).start(),
      icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
      label: const Text('Record track'),
    );
  }
}

class _RoutesTab extends ConsumerWidget {
  const _RoutesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(savedRoutesProvider);
    final units = ref.watch(unitSystemProvider);
    return routesAsync.when(
      data: (routes) {
        if (routes.isEmpty) return const _EmptyTab(icon: Icons.route_rounded, message: 'No saved routes yet.');
        return ListView.builder(
          itemCount: routes.length,
          itemBuilder: (context, i) => _RouteListItem(route: routes[i], units: units, ref: ref),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _EmptyTab(icon: Icons.error_outline, message: 'Could not load routes.'),
    );
  }
}

class _RouteListItem extends StatelessWidget {
  const _RouteListItem({required this.route, required this.units, required this.ref});
  final SavedRoute route;
  final UnitSystem units;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(route.id),
      direction: DismissDirection.endToStart,
      background: Container(color: AppColors.danger, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: AppSpacing.lg), child: const Icon(Icons.delete, color: Colors.white)),
      onDismissed: (_) => ref.read(savedRoutesProvider.notifier).remove(route.id),
      child: ListTile(
        leading: Icon(_profileIcon(route.profile)),
        title: Text(route.name),
        subtitle: Text('${Formatters.distance(route.distanceMeters, units)} · ${Formatters.duration(Duration(seconds: route.durationSeconds.round()))}'),
      ),
    );
  }

  IconData _profileIcon(TravelProfile p) => switch (p) {
        TravelProfile.drive => Icons.directions_car_filled_rounded,
        TravelProfile.walk => Icons.directions_walk_rounded,
        TravelProfile.bike => Icons.directions_bike_rounded,
      };
}

class _TracksTab extends ConsumerWidget {
  const _TracksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(tracksProvider);
    final units = ref.watch(unitSystemProvider);
    return tracksAsync.when(
      data: (tracks) {
        if (tracks.isEmpty) return const _EmptyTab(icon: Icons.timeline_rounded, message: 'No recorded tracks yet.');
        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final track = tracks[i];
            return Dismissible(
              key: ValueKey(track.id),
              direction: DismissDirection.endToStart,
              background: Container(color: AppColors.danger, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: AppSpacing.lg), child: const Icon(Icons.delete, color: Colors.white)),
              onDismissed: (_) => ref.read(tracksProvider.notifier).remove(track.id),
              child: ListTile(
                leading: const Icon(Icons.timeline_rounded),
                title: Text(track.name),
                subtitle: Text(
                  '${Formatters.distance(track.distanceMeters, units)} · ${Formatters.duration(track.duration)} · '
                  '↑${Formatters.elevation(track.elevationGainMeters, units)} ↓${Formatters.elevation(track.elevationLossMeters, units)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () {
                    final gpx = ref.read(gpxServiceProvider).exportTrack(track);
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('${track.name}.gpx'),
                        content: SingleChildScrollView(child: Text(gpx, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _EmptyTab(icon: Icons.error_outline, message: 'Could not load tracks.'),
    );
  }
}

class _WaypointsTab extends ConsumerWidget {
  const _WaypointsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waypointsAsync = ref.watch(waypointsProvider);
    return waypointsAsync.when(
      data: (waypoints) {
        if (waypoints.isEmpty) return const _EmptyTab(icon: Icons.place_rounded, message: 'No saved waypoints yet.');
        return ListView.builder(
          itemCount: waypoints.length,
          itemBuilder: (context, i) {
            final wp = waypoints[i];
            return Dismissible(
              key: ValueKey(wp.id),
              direction: DismissDirection.endToStart,
              background: Container(color: AppColors.danger, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: AppSpacing.lg), child: const Icon(Icons.delete, color: Colors.white)),
              onDismissed: (_) => ref.read(waypointsProvider.notifier).remove(wp.id),
              child: ListTile(
                leading: Icon(placeIconFor(_categoryFor(wp.icon))),
                title: Text(wp.name),
                subtitle: wp.notes != null ? Text(wp.notes!) : null,
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _EmptyTab(icon: Icons.error_outline, message: 'Could not load waypoints.'),
    );
  }
}

// Waypoint icons/categories are intentionally separate enums (a waypoint
// icon is a user-facing pin style, not a POI classification) — map the few
// that overlap for a shared glyph set rather than duplicating icon logic.
PlaceCategory _categoryFor(WaypointIcon icon) => switch (icon) {
      WaypointIcon.water => PlaceCategory.water,
      WaypointIcon.campsite => PlaceCategory.campground,
      WaypointIcon.summit => PlaceCategory.summit,
      WaypointIcon.parking => PlaceCategory.parking,
      _ => PlaceCategory.other,
    };

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.glass.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
