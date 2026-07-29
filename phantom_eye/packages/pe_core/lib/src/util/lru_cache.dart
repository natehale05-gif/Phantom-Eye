import 'dart:collection';

/// A bounded least-recently-used cache.
///
/// Ports the touch-on-hit / evict-oldest pattern that the legacy app grew
/// independently in three places (`labelTexture.ts`, `streetlabels.ts` and
/// `trails.ts`) after each one was found growing without bound. Dart's
/// [LinkedHashMap] preserves insertion order, so recency is maintained by
/// removing and re-inserting on every hit — exactly what the JS `Map`
/// versions did.
final class LruCache<K, V> {
  LruCache(this.maxEntries) : assert(maxEntries > 0);

  final int maxEntries;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  int get length => _entries.length;

  bool containsKey(K key) => _entries.containsKey(key);

  V? operator [](K key) => get(key);

  /// Look up `key`, bumping it to most-recently-used on a hit.
  V? get(K key) {
    final hit = _entries.remove(key);
    if (hit == null) return null;
    _entries[key] = hit;
    return hit;
  }

  void operator []=(K key, V value) => put(key, value);

  /// Insert or replace, evicting the oldest entry if now over capacity.
  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  V? remove(K key) => _entries.remove(key);

  void clear() => _entries.clear();

  Iterable<K> get keys => _entries.keys;
}
