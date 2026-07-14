import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// JSON-file-per-collection storage for growing datasets: recorded tracks,
/// saved routes, and waypoints. Good enough for a single-user, offline-first
/// app; if Phantom Eye grows account sync this is the seam to swap in a
/// real database (e.g. `drift`/sqlite) or a backend.
class FileStore {
  FileStore(this._root);

  final Directory _root;

  static Future<FileStore> create() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory('${dir.path}/phantom_eye');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return FileStore(root);
  }

  File _fileFor(String collection) => File('${_root.path}/$collection.json');

  Future<List<Map<String, dynamic>>> readCollection(String collection) async {
    final file = _fileFor(collection);
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeCollection(String collection, List<Map<String, dynamic>> items) async {
    final file = _fileFor(collection);
    await file.writeAsString(jsonEncode(items));
  }

  /// For exporting a single GPX/text file (e.g. track export) to a
  /// user-visible location under the app's documents directory.
  Future<File> writeExportFile(String filename, String contents) async {
    final exportsDir = Directory('${_root.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final file = File('${exportsDir.path}/$filename');
    await file.writeAsString(contents);
    return file;
  }
}

abstract final class FileCollections {
  static const String tracks = 'tracks';
  static const String savedRoutes = 'saved_routes';
  static const String waypoints = 'waypoints';
  static const String meshNodes = 'mesh_nodes';
}
