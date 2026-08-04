/// A small synchronous-read, asynchronous-write key/value store.
///
/// This is the persistence boundary for everything the app remembers between
/// launches: waypoints, saved gas prices, recent searches, layer toggles. The
/// legacy app reached straight for `localStorage`; naming the boundary here
/// keeps `pe_domain` free of any platform dependency, so every store built on
/// it is testable with [InMemoryKeyValueStore] and no device.
///
/// Reads are synchronous because the callers are render paths — a place card
/// asks for a saved price while building its widget, and an `await` there
/// would mean a frame with the price missing. Concrete implementations are
/// expected to hydrate once at startup and serve reads from memory, which is
/// exactly what `shared_preferences` does.
///
/// ## Not for secrets
///
/// **Never store the Cesium ion token — or any credential — here.** This
/// backs onto ordinary app preferences, which are world-readable on a rooted
/// or jailbroken device and sit in plain text in the profile directory on
/// desktop. Tokens belong in platform secure storage, in a
/// `--dart-define`-injected build constant, or in onboarding input held only
/// for the session. The legacy app kept its token in `localStorage` *and*
/// baked a default into the bundle; the rewrite must not inherit either.
abstract interface class KeyValueStore {
  /// The stored value, or null when the key was never written.
  String? read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

/// An in-memory [KeyValueStore] for tests and for a first run before any
/// platform store is wired up.
final class InMemoryKeyValueStore implements KeyValueStore {
  InMemoryKeyValueStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  /// A snapshot of everything stored, for assertions.
  Map<String, String> get entries => Map.unmodifiable(_values);

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

/// A [KeyValueStore] whose writes always fail.
///
/// Private-mode browsers and locked-down device profiles reject writes, and
/// the legacy code swallowed those failures everywhere (`catch { /* ignore
/// private-mode storage failures */ }`) so the session kept working with
/// whatever was already in memory. Stores in this package must behave the
/// same way, and this makes that testable rather than assumed.
final class FailingKeyValueStore implements KeyValueStore {
  FailingKeyValueStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async {
    throw StateError('storage unavailable');
  }

  @override
  Future<void> remove(String key) async {
    throw StateError('storage unavailable');
  }
}

/// Storage keys, kept byte-identical to the legacy app's.
///
/// A future migration path can only read the old data if the keys match, so
/// these are deliberately not renamed to something tidier. The `nomos:`
/// prefix is a leftover from an earlier name for the app.
abstract final class StorageKeys {
  /// Saved waypoints. Ported from `WAYPOINTS_KEY` in `src/field.ts:26`.
  static const String waypoints = 'phantom-eye.waypoints';

  /// User-reported fuel prices. Ported from `src/gasprices.ts:22`.
  static const String gasPrices = 'phantom-eye.gasPrices';

  /// Recent search results. Ported from `RECENTS_KEY` in `src/main.ts:519`.
  static const String recents = 'phantom-eye.recents';

  /// Street-label overlay toggle. Ported from `src/main.ts:161`.
  static const String streetLabels = 'nomos:labels';

  /// Per-layer trail toggle. Ported from `src/main.ts:202`.
  static String trailLayer(String layerId) => 'nomos:trail:$layerId';
}
