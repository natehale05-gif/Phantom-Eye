import 'package:pe_core/pe_core.dart';

import '../trails/trail_layers.dart';

/// Which overlays are switched on, persisted across launches.
///
/// Ported from the toggle handling in `src/main.ts:161` and `:202`. Values are
/// stored as the literal strings `'on'` / `'off'` rather than as JSON
/// booleans, matching the legacy writes exactly so existing settings survive a
/// migration.
///
/// Street labels default to **on** and every trail layer defaults to **off** —
/// the same defaults the original applied by treating a missing key as its
/// respective fallback. Trails cost an Overpass round trip per view change, so
/// they are opt-in; labels are local and expected.
final class LayerSettings {
  const LayerSettings(this._storage);

  final KeyValueStore _storage;

  static const String _on = 'on';
  static const String _off = 'off';

  bool get streetLabelsEnabled =>
      _read(StorageKeys.streetLabels, defaultValue: true);

  Future<void> setStreetLabelsEnabled(bool enabled) =>
      _write(StorageKeys.streetLabels, enabled);

  bool isTrailLayerEnabled(TrailLayerId layer) =>
      _read(StorageKeys.trailLayer(layer.id), defaultValue: false);

  Future<void> setTrailLayerEnabled(TrailLayerId layer, bool enabled) =>
      _write(StorageKeys.trailLayer(layer.id), enabled);

  /// Every trail layer currently switched on.
  Set<TrailLayerId> get enabledTrailLayers => {
    for (final layer in TrailLayerId.values)
      if (isTrailLayerEnabled(layer)) layer,
  };

  bool _read(String key, {required bool defaultValue}) {
    final raw = _storage.read(key);
    // Anything other than the two known values — a half-written key, a value
    // from a future version — falls back rather than being coerced.
    if (raw == _on) return true;
    if (raw == _off) return false;
    return defaultValue;
  }

  Future<void> _write(String key, bool enabled) async {
    try {
      await _storage.write(key, enabled ? _on : _off);
    } on Object {
      // Private-mode storage: the toggle still applies for this session.
    }
  }
}
