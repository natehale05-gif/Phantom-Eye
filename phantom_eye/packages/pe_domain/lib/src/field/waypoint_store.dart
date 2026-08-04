import 'dart:convert';

import 'package:pe_core/pe_core.dart';

/// Saved waypoints, persisted through a [KeyValueStore].
///
/// Ported from `loadWaypoints` / `saveWaypoints` in `src/field.ts:445`.
///
/// Two behaviours are carried over deliberately, and one is fixed:
///
///  * a **write failure is swallowed** — private-mode storage and locked-down
///    profiles reject writes, and the original kept the session working with
///    the in-memory list rather than failing the user's tap;
///  * a **corrupt blob yields an empty list** rather than an exception;
///  * **individual corrupt entries are now dropped** instead of being passed
///    through. The original checked only `Array.isArray(parsed)` and returned
///    whatever was inside, so one truncated entry became a waypoint with no
///    coordinate that broke rendering for every waypoint after it.
final class WaypointStore {
  WaypointStore(this._storage, {this.key = StorageKeys.waypoints});

  final KeyValueStore _storage;

  /// Storage key. Overridable so several lists can share one backing store.
  final String key;

  List<Waypoint>? _cache;

  /// Every saved waypoint, in stored order.
  List<Waypoint> all() => List.unmodifiable(_load());

  List<Waypoint> _load() {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = _storage.read(key);
    final out = <Waypoint>[];
    if (raw != null && raw.isNotEmpty) {
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
      if (decoded is List) {
        for (final entry in decoded) {
          final waypoint = Waypoint.fromJson(entry);
          if (waypoint != null) out.add(waypoint);
        }
      }
    }
    return _cache = out;
  }

  /// Add a waypoint and persist. Returns the stored list.
  Future<List<Waypoint>> add(Waypoint waypoint) async {
    final next = [..._load(), waypoint];
    return _commit(next);
  }

  /// Remove by id. Removing an unknown id is a no-op, not an error.
  Future<List<Waypoint>> remove(String id) async {
    final next = [
      for (final w in _load())
        if (w.id != id) w,
    ];
    return _commit(next);
  }

  /// Replace a waypoint in place, keeping its position in the list.
  Future<List<Waypoint>> update(Waypoint waypoint) async {
    final next = [
      for (final w in _load())
        if (w.id == waypoint.id) waypoint else w,
    ];
    return _commit(next);
  }

  Future<List<Waypoint>> clear() => _commit(const []);

  Future<List<Waypoint>> _commit(List<Waypoint> next) async {
    // The in-memory list is updated first and kept even if the write fails,
    // so the current session still reflects what the user did.
    _cache = next;
    try {
      await _storage.write(key, jsonEncode([for (final w in next) w.toJson()]));
    } on Object {
      // Private-mode / read-only storage. Deliberately swallowed.
    }
    return List.unmodifiable(next);
  }
}
