import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/file_store.dart';
import '../models/saved_route.dart';
import '../models/track.dart';
import '../models/waypoint.dart';
import 'core_providers.dart';

class WaypointsNotifier extends AsyncNotifier<List<Waypoint>> {
  @override
  Future<List<Waypoint>> build() async {
    final store = ref.read(fileStoreProvider);
    final raw = await store.readCollection(FileCollections.waypoints);
    return raw.map(Waypoint.fromJson).toList();
  }

  Future<void> add(Waypoint waypoint) async {
    final current = state.valueOrNull ?? [];
    final updated = [waypoint, ...current];
    state = AsyncData(updated);
    await ref.read(fileStoreProvider).writeCollection(
          FileCollections.waypoints,
          updated.map((w) => w.toJson()).toList(),
        );
  }

  Future<void> remove(String id) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((w) => w.id != id).toList();
    state = AsyncData(updated);
    await ref.read(fileStoreProvider).writeCollection(
          FileCollections.waypoints,
          updated.map((w) => w.toJson()).toList(),
        );
  }
}

final waypointsProvider = AsyncNotifierProvider<WaypointsNotifier, List<Waypoint>>(WaypointsNotifier.new);

class SavedRoutesNotifier extends AsyncNotifier<List<SavedRoute>> {
  @override
  Future<List<SavedRoute>> build() async {
    final store = ref.read(fileStoreProvider);
    final raw = await store.readCollection(FileCollections.savedRoutes);
    return raw.map(SavedRoute.fromJson).toList();
  }

  Future<void> add(SavedRoute route) async {
    final current = state.valueOrNull ?? [];
    final updated = [route, ...current];
    state = AsyncData(updated);
    await ref.read(fileStoreProvider).writeCollection(
          FileCollections.savedRoutes,
          updated.map((r) => r.toJson()).toList(),
        );
  }

  Future<void> remove(String id) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((r) => r.id != id).toList();
    state = AsyncData(updated);
    await ref.read(fileStoreProvider).writeCollection(
          FileCollections.savedRoutes,
          updated.map((r) => r.toJson()).toList(),
        );
  }
}

final savedRoutesProvider = AsyncNotifierProvider<SavedRoutesNotifier, List<SavedRoute>>(SavedRoutesNotifier.new);

class TracksNotifier extends AsyncNotifier<List<Track>> {
  @override
  Future<List<Track>> build() async {
    final store = ref.read(fileStoreProvider);
    final raw = await store.readCollection(FileCollections.tracks);
    return raw.map(Track.fromJson).toList();
  }

  Future<void> add(Track track) async {
    final current = state.valueOrNull ?? [];
    final updated = [track, ...current];
    state = AsyncData(updated);
    await ref.read(fileStoreProvider).writeCollection(
          FileCollections.tracks,
          updated.map((t) => t.toJson()).toList(),
        );
  }

  Future<void> remove(String id) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((t) => t.id != id).toList();
    state = AsyncData(updated);
    await ref.read(fileStoreProvider).writeCollection(
          FileCollections.tracks,
          updated.map((t) => t.toJson()).toList(),
        );
  }
}

final tracksProvider = AsyncNotifierProvider<TracksNotifier, List<Track>>(TracksNotifier.new);
