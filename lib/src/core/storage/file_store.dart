import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// JSON-blob-per-collection storage for growing datasets: recorded tracks,
/// saved routes, and waypoints.
///
/// Backed by [SharedPreferences] (not `dart:io` files) so the exact same
/// code path works on iOS, Android, *and* web (SharedPreferences uses
/// `localStorage` under the hood on web) — this app ships a web build for
/// browser-based QA (see `.github/workflows/`), and `dart:io`'s
/// `File`/`Directory` simply don't exist there.
///
/// Good enough for a single-user, offline-first app; if Phantom Eye grows
/// account sync this is the seam to swap in a real database (e.g.
/// `drift`/sqlite) or a backend.
class FileStore {
  FileStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<FileStore> create() async {
    return FileStore(await SharedPreferences.getInstance());
  }

  String _keyFor(String collection) => 'collection.$collection';

  Future<List<Map<String, dynamic>>> readCollection(String collection) async {
    final raw = _prefs.getString(_keyFor(collection));
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeCollection(String collection, List<Map<String, dynamic>> items) async {
    await _prefs.setString(_keyFor(collection), jsonEncode(items));
  }
}

abstract final class FileCollections {
  static const String tracks = 'tracks';
  static const String savedRoutes = 'saved_routes';
  static const String waypoints = 'waypoints';
  static const String meshNodes = 'mesh_nodes';
}
