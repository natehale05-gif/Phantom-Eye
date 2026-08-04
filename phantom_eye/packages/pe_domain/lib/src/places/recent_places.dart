import 'dart:convert';

import 'package:pe_core/pe_core.dart';

/// How many recent searches are kept.
///
/// Ported from the `slice(0, 8)` in `src/main.ts:527`.
const int kMaxRecentPlaces = 8;

/// Identity used to collapse repeat visits to the same place.
///
/// OSM identity when available, otherwise name plus a 4-decimal coordinate —
/// the same key [parsePhotonSearch] uses to dedupe within a single set of
/// search results, and the same one [gasStationKey] uses.
String recentPlaceKey(Place place) =>
    place.osmKey ??
    '${place.name.toLowerCase()}@'
        '${place.position.lat.toStringAsFixed(4)},'
        '${place.position.lon.toStringAsFixed(4)}';

/// Recently visited places, most recent first.
///
/// Ported from the recents block in `src/main.ts:518`, with one fix.
///
/// **The original deduped on exact floating-point coordinate equality**
/// (`p.lon === r.lon && p.lat === r.lat`). Photon does not return bit-identical
/// coordinates for the same POI across searches — the geocoder re-derives the
/// centroid, and a way's centre shifts as OSM is edited — so revisiting a
/// place stacked a fresh row on top of the old one. With only eight slots,
/// three visits to the same restaurant evicted five genuinely different
/// places. Keying on OSM identity (with the rounded-coordinate fallback)
/// collapses those correctly.
final class RecentPlacesStore {
  RecentPlacesStore(
    this._storage, {
    this.key = StorageKeys.recents,
    this.maxEntries = kMaxRecentPlaces,
  });

  final KeyValueStore _storage;

  /// Storage key. Overridable so tests can isolate.
  final String key;

  final int maxEntries;

  List<Place>? _cache;

  /// The stored list, most recent first.
  List<Place> all() => List.unmodifiable(_load());

  List<Place> _load() {
    final cached = _cache;
    if (cached != null) return cached;

    final out = <Place>[];
    final raw = _storage.read(key);
    if (raw != null && raw.isNotEmpty) {
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
      if (decoded is List) {
        for (final entry in decoded) {
          final place = Place.fromJson(entry);
          // Corrupt entries are dropped; the rest of the history survives.
          if (place != null) out.add(place);
          if (out.length >= maxEntries) break;
        }
      }
    }
    return _cache = out;
  }

  /// Record a visit, moving the place to the front.
  Future<List<Place>> remember(Place place) async {
    final identity = recentPlaceKey(place);
    final next = <Place>[
      place,
      for (final p in _load())
        if (recentPlaceKey(p) != identity) p,
    ];
    if (next.length > maxEntries) next.removeRange(maxEntries, next.length);

    _cache = next;
    try {
      await _storage.write(key, jsonEncode([for (final p in next) p.toJson()]));
    } on Object {
      // Private-mode storage. The list still holds for this session.
    }
    return List.unmodifiable(next);
  }

  Future<List<Place>> clear() async {
    _cache = const [];
    try {
      await _storage.remove(key);
    } on Object {
      // Deliberately swallowed, as above.
    }
    return const [];
  }
}
