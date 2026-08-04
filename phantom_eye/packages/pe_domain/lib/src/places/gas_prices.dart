import 'dart:convert';

import 'package:pe_core/pe_core.dart';

/// Identify a gas station for price storage.
///
/// Ported from `stationKey` in `src/gasprices.ts:24`. OSM identity is used
/// when available; otherwise the name and a 4-decimal coordinate (~11 m)
/// stand in, which is the same fallback key `parsePhotonSearch` uses so a
/// station found by search and the same station found by tapping the map
/// resolve to one entry.
String gasStationKey(Place place) =>
    place.osmKey ??
    '${place.name.toLowerCase()}@'
        '${place.position.lat.toStringAsFixed(4)},'
        '${place.position.lon.toStringAsFixed(4)}';

/// Render a price the way the place card shows it.
///
/// Ported from `formatPrice` in `src/gasprices.ts:64`.
String formatGasPrice(double pricePerGallon) =>
    '\$${pricePerGallon.toStringAsFixed(2)}/gal';

/// User-reported fuel prices, persisted through a [KeyValueStore].
///
/// Ported from `src/gasprices.ts`. The whole map is held in memory after the
/// first read — the original did the same, because `getGasPrice` is called
/// once per place-card render and re-parsing the blob each time was wasteful.
///
/// The legacy version's staleness across browser tabs does not arise here:
/// that was an artefact of two documents sharing one `localStorage`, and a
/// Flutter app is a single process.
final class GasPriceBook {
  GasPriceBook(this._storage, {this.key = StorageKeys.gasPrices});

  final KeyValueStore _storage;

  /// Storage key. Overridable so tests can isolate.
  final String key;

  Map<String, GasPriceReport>? _cache;

  Map<String, GasPriceReport> _load() {
    final cached = _cache;
    if (cached != null) return cached;

    final out = <String, GasPriceReport>{};
    final raw = _storage.read(key);
    if (raw != null && raw.isNotEmpty) {
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final key = entry.key;
          if (key is! String) continue;
          // A corrupt or negative-price entry is dropped, not surfaced as a
          // nonsense figure on the card.
          final report = GasPriceReport.fromJson(entry.value);
          if (report != null) out[key] = report;
        }
      }
    }
    return _cache = out;
  }

  /// The last reported price for a station, or null.
  GasPriceReport? priceFor(Place place) => _load()[gasStationKey(place)];

  /// Record a price. Returns the stored report.
  ///
  /// Throws [ArgumentError] for a non-positive or non-finite price — that is
  /// a caller bug, not user data, and silently storing it would put a bogus
  /// figure on the card for good.
  Future<GasPriceReport> report(
    Place place,
    double pricePerGallon, {
    DateTime? at,
  }) async {
    if (!pricePerGallon.isFinite || pricePerGallon <= 0) {
      throw ArgumentError.value(
        pricePerGallon,
        'pricePerGallon',
        'must be a positive, finite price',
      );
    }
    final report = GasPriceReport(
      pricePerGallon: pricePerGallon,
      reportedAt: at ?? DateTime.now(),
    );
    final next = {..._load(), gasStationKey(place): report};
    _cache = next;
    try {
      await _storage.write(
        key,
        jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}),
      );
    } on Object {
      // Private-mode storage. The report still holds for this session.
    }
    return report;
  }

  /// Number of stations with a stored price.
  int get length => _load().length;
}
