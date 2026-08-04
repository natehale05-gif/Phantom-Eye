import 'dart:convert';

import 'package:pe_core/pe_core.dart';
import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

Place _place(
  String name, {
  double lon = -123.262,
  double lat = 44.5646,
  OsmType? osmType,
  int? osmId,
}) => Place(
  name: name,
  detail: 'somewhere',
  position: LngLat(lon, lat),
  osmType: osmType,
  osmId: osmId,
);

void main() {
  group('gasStationKey', () {
    test('OSM identity wins when available', () {
      expect(
        gasStationKey(_place('Shell', osmType: OsmType.node, osmId: 42)),
        'node/42',
      );
    });

    test('falls back to name plus 4dp coordinates', () {
      expect(gasStationKey(_place('Shell')), 'shell@44.5646,-123.2620');
    });

    test('the fallback is case-insensitive on the name', () {
      expect(gasStationKey(_place('SHELL')), gasStationKey(_place('shell')));
    });

    test('the fallback tolerates coordinate drift under ~11 m', () {
      // A station found by search and the same station found by tapping the
      // map must resolve to one entry — the same 4dp rounding the Photon
      // parser uses for its own dedupe.
      expect(
        gasStationKey(_place('Shell', lon: -123.26201, lat: 44.564603)),
        gasStationKey(_place('Shell')),
      );
    });

    test('a node and a way with the same id are different stations', () {
      expect(
        gasStationKey(_place('X', osmType: OsmType.node, osmId: 7)),
        isNot(gasStationKey(_place('X', osmType: OsmType.way, osmId: 7))),
      );
    });
  });

  group('formatGasPrice', () {
    test('always two decimals', () {
      expect(formatGasPrice(4.299), r'$4.30/gal');
      expect(formatGasPrice(4), r'$4.00/gal');
      expect(formatGasPrice(3.5), r'$3.50/gal');
      expect(formatGasPrice(10.125), r'$10.13/gal');
    });
  });

  group('GasPriceBook', () {
    test('a reported price is readable back', () async {
      final storage = InMemoryKeyValueStore();
      final book = GasPriceBook(storage);
      final station = _place('Shell', osmType: OsmType.node, osmId: 42);

      expect(book.priceFor(station), isNull);
      final at = DateTime.utc(2026, 7, 30, 10);
      await book.report(station, 4.29, at: at);

      final report = book.priceFor(station)!;
      expect(report.pricePerGallon, 4.29);
      expect(report.reportedAt, at);

      // A fresh book over the same storage sees it too.
      expect(GasPriceBook(storage).priceFor(station)!.pricePerGallon, 4.29);
    });

    test('reporting again replaces the previous price', () async {
      final book = GasPriceBook(InMemoryKeyValueStore());
      final station = _place('Shell', osmType: OsmType.node, osmId: 42);
      await book.report(station, 4.29);
      await book.report(station, 4.09);
      expect(book.priceFor(station)!.pricePerGallon, 4.09);
      expect(book.length, 1);
    });

    test('stations are kept apart', () async {
      final book = GasPriceBook(InMemoryKeyValueStore());
      await book.report(_place('A', osmType: OsmType.node, osmId: 1), 4.29);
      await book.report(_place('B', osmType: OsmType.node, osmId: 2), 3.99);
      expect(book.length, 2);
      expect(
        book
            .priceFor(_place('A', osmType: OsmType.node, osmId: 1))!
            .pricePerGallon,
        4.29,
      );
    });

    test('a nonsense price is rejected rather than stored forever', () {
      final book = GasPriceBook(InMemoryKeyValueStore());
      final station = _place('Shell');
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => book.report(station, bad),
          throwsA(isA<ArgumentError>()),
          reason: '$bad',
        );
      }
    });

    test('corrupt stored entries are dropped, good ones survive', () {
      final storage = InMemoryKeyValueStore({
        StorageKeys.gasPrices: jsonEncode({
          'node/1': {'price': 4.29, 'reportedAt': '2026-07-30T10:00:00.000Z'},
          'node/2': {'price': -5, 'reportedAt': '2026-07-30T10:00:00.000Z'},
          'node/3': {'price': 4.0, 'reportedAt': 'not a date'},
          'node/4': 'garbage',
        }),
      });
      final book = GasPriceBook(storage);
      expect(book.length, 1);
      expect(
        book
            .priceFor(_place('X', osmType: OsmType.node, osmId: 1))!
            .pricePerGallon,
        4.29,
      );
    });

    test('a corrupt blob yields no prices, not an exception', () {
      for (final raw in ['not json', '[]', '42', '']) {
        final storage = InMemoryKeyValueStore({StorageKeys.gasPrices: raw});
        expect(GasPriceBook(storage).length, 0, reason: raw);
      }
    });

    test('a write failure keeps the price for the session', () async {
      final book = GasPriceBook(FailingKeyValueStore());
      final station = _place('Shell');
      await book.report(station, 4.29);
      expect(book.priceFor(station)!.pricePerGallon, 4.29);
    });

    test('formatRelativeTime from pe_core renders the age', () {
      final at = DateTime.utc(2026, 7, 30, 10);
      expect(
        formatRelativeTime(at, now: at.add(const Duration(minutes: 30))),
        '30 min ago',
      );
      expect(
        formatRelativeTime(at, now: at.add(const Duration(hours: 2))),
        '2 hrs ago',
      );
    });
  });

  group('RecentPlacesStore', () {
    test('most recent first', () async {
      final store = RecentPlacesStore(InMemoryKeyValueStore());
      await store.remember(_place('A', osmType: OsmType.node, osmId: 1));
      await store.remember(_place('B', osmType: OsmType.node, osmId: 2));
      await store.remember(_place('C', osmType: OsmType.node, osmId: 3));
      expect(store.all().map((p) => p.name), ['C', 'B', 'A']);
    });

    test(
      'REGRESSION: a revisit moves the place instead of stacking a duplicate',
      () async {
        // The original deduped on exact floating-point coordinate equality.
        // Photon does not return bit-identical coordinates for the same POI
        // across searches — the geocoder re-derives the centroid, and a way's
        // centre shifts as OSM is edited — so revisiting a place stacked a
        // fresh row on top of the old one. With eight slots, three visits to
        // one restaurant evicted five genuinely different places.
        final store = RecentPlacesStore(InMemoryKeyValueStore());
        final first = _place('Block 15', osmType: OsmType.way, osmId: 99);
        const drifted = Place(
          name: 'Block 15',
          detail: 'somewhere',
          // A metre or so away, and not bit-identical.
          position: LngLat(-123.2620009, 44.5646004),
          osmType: OsmType.way,
          osmId: 99,
        );

        await store.remember(first);
        await store.remember(_place('Other', osmType: OsmType.node, osmId: 1));
        await store.remember(drifted);

        expect(store.all(), hasLength(2), reason: 'not three');
        expect(store.all().first.name, 'Block 15');
        expect(store.all().last.name, 'Other');
      },
    );

    test('the rounded-coordinate fallback catches places with no OSM id', () {
      final a = _place('Interzone');
      final b = _place('Interzone', lon: -123.26201, lat: 44.564603);
      expect(recentPlaceKey(a), recentPlaceKey(b));
    });

    test('two branches of one chain stay distinct', () async {
      final store = RecentPlacesStore(InMemoryKeyValueStore());
      await store.remember(
        _place('Starbucks', osmType: OsmType.node, osmId: 1),
      );
      await store.remember(
        _place('Starbucks', osmType: OsmType.node, osmId: 2),
      );
      expect(store.all(), hasLength(2));
    });

    test('the list is capped at eight', () async {
      final store = RecentPlacesStore(InMemoryKeyValueStore());
      for (var i = 0; i < 20; i++) {
        await store.remember(_place('P$i', osmType: OsmType.node, osmId: i));
      }
      expect(store.all(), hasLength(kMaxRecentPlaces));
      expect(store.all().first.name, 'P19', reason: 'the newest survives');
      expect(store.all().last.name, 'P12');
    });

    test('the cap is overridable', () async {
      final store = RecentPlacesStore(InMemoryKeyValueStore(), maxEntries: 3);
      for (var i = 0; i < 10; i++) {
        await store.remember(_place('P$i', osmType: OsmType.node, osmId: i));
      }
      expect(store.all(), hasLength(3));
    });

    test('details survive the round trip', () async {
      final storage = InMemoryKeyValueStore();
      await RecentPlacesStore(storage).remember(
        const Place(
          name: 'Block 15',
          detail: '300 SW Jefferson Ave, Corvallis',
          position: LngLat(-123.262, 44.5646),
          category: 'pub',
          categoryId: 'food',
          osmType: OsmType.way,
          osmId: 99,
          details: PlaceDetails(
            phone: '+1 541 555 0100',
            website: 'https://example.test',
            openingHours: 'Mo-Su 11:00-23:00',
            address: '300 SW Jefferson Ave, Corvallis, Oregon, 97333',
          ),
        ),
      );

      final back = RecentPlacesStore(storage).all().single;
      expect(back.name, 'Block 15');
      expect(back.detail, '300 SW Jefferson Ave, Corvallis');
      expect(back.category, 'pub');
      expect(back.categoryId, 'food');
      expect(back.osmType, OsmType.way);
      expect(back.osmId, 99);
      expect(back.details.phone, '+1 541 555 0100');
      expect(back.details.openingHours, 'Mo-Su 11:00-23:00');
    });

    test('REGRESSION: one corrupt entry does not take the history with it', () {
      final storage = InMemoryKeyValueStore({
        StorageKeys.recents: jsonEncode([
          {'name': 'Kept', 'lon': -123.26, 'lat': 44.56},
          {'name': 'No coordinate'},
          {'lon': -123.26, 'lat': 44.56},
          'garbage',
          {'name': 'Also kept', 'lon': -123.27, 'lat': 44.57},
        ]),
      });
      expect(RecentPlacesStore(storage).all().map((p) => p.name), [
        'Kept',
        'Also kept',
      ]);
    });

    test('a corrupt blob yields an empty history', () {
      for (final raw in ['not json', '{}', '42', '']) {
        final storage = InMemoryKeyValueStore({StorageKeys.recents: raw});
        expect(RecentPlacesStore(storage).all(), isEmpty, reason: raw);
      }
    });

    test('clear empties the list', () async {
      final storage = InMemoryKeyValueStore();
      final store = RecentPlacesStore(storage);
      await store.remember(_place('A'));
      await store.clear();
      expect(store.all(), isEmpty);
      expect(RecentPlacesStore(storage).all(), isEmpty);
    });

    test('a write failure keeps the list for the session', () async {
      final store = RecentPlacesStore(FailingKeyValueStore());
      await store.remember(_place('A'));
      expect(store.all(), hasLength(1));
    });
  });

  group('curated places', () {
    test('the ids are unique and looked up', () {
      final ids = kCuratedPlaces.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final place in kCuratedPlaces) {
        expect(curatedPlaceById(place.id), same(place));
      }
      expect(curatedPlaceById('atlantis'), isNull);
    });

    test('every framing is a plausible downward camera', () {
      for (final place in kCuratedPlaces) {
        expect(place.cameraHeightMeters, greaterThan(0), reason: place.id);
        expect(
          place.pitchDegrees,
          lessThan(0),
          reason: '${place.id} looks down',
        );
        expect(place.pitchDegrees, greaterThan(-90), reason: place.id);
        expect(
          place.headingDegrees,
          inInclusiveRange(0, 360),
          reason: place.id,
        );
        expect(place.position.isFinite, isTrue, reason: place.id);
        expect(
          place.position.lat.abs(),
          lessThanOrEqualTo(90),
          reason: place.id,
        );
        expect(
          place.position.lon.abs(),
          lessThanOrEqualTo(180),
          reason: place.id,
        );
        expect(place.name, isNotEmpty, reason: place.id);
        expect(place.region, isNotEmpty, reason: place.id);
      }
    });

    test(
      'the southern hemisphere is represented, so sign handling is real',
      () {
        expect(
          kCuratedPlaces.where((p) => p.position.lat < 0),
          isNotEmpty,
          reason: 'Sydney',
        );
        expect(kCuratedPlaces.where((p) => p.position.lon < 0), isNotEmpty);
      },
    );
  });

  group('LayerSettings', () {
    test('street labels default on, trails default off', () {
      final settings = LayerSettings(InMemoryKeyValueStore());
      expect(settings.streetLabelsEnabled, isTrue);
      for (final layer in TrailLayerId.values) {
        expect(settings.isTrailLayerEnabled(layer), isFalse, reason: layer.id);
      }
      expect(settings.enabledTrailLayers, isEmpty);
    });

    test('toggles round-trip', () async {
      final storage = InMemoryKeyValueStore();
      final settings = LayerSettings(storage);

      await settings.setStreetLabelsEnabled(false);
      expect(settings.streetLabelsEnabled, isFalse);
      expect(LayerSettings(storage).streetLabelsEnabled, isFalse);

      await settings.setTrailLayerEnabled(TrailLayerId.bike, true);
      expect(settings.isTrailLayerEnabled(TrailLayerId.bike), isTrue);
      expect(settings.isTrailLayerEnabled(TrailLayerId.hiking), isFalse);
      expect(settings.enabledTrailLayers, {TrailLayerId.bike});
    });

    test('values are stored as the legacy on/off strings', () async {
      final storage = InMemoryKeyValueStore();
      final settings = LayerSettings(storage);
      await settings.setStreetLabelsEnabled(true);
      await settings.setTrailLayerEnabled(TrailLayerId.offroad, false);

      expect(storage.entries['nomos:labels'], 'on');
      expect(storage.entries['nomos:trail:offroad'], 'off');
    });

    test('an unrecognised stored value falls back to the default', () {
      final settings = LayerSettings(
        InMemoryKeyValueStore({
          'nomos:labels': 'maybe',
          'nomos:trail:bike': 'true',
        }),
      );
      expect(settings.streetLabelsEnabled, isTrue, reason: 'labels default on');
      expect(
        settings.isTrailLayerEnabled(TrailLayerId.bike),
        isFalse,
        reason: 'trails default off; "true" is not "on"',
      );
    });

    test('every layer gets its own key', () async {
      final storage = InMemoryKeyValueStore();
      final settings = LayerSettings(storage);
      for (final layer in TrailLayerId.values) {
        await settings.setTrailLayerEnabled(layer, true);
      }
      expect(storage.entries.keys, hasLength(TrailLayerId.values.length));
      expect(settings.enabledTrailLayers, TrailLayerId.values.toSet());
    });

    test('a write failure still reports the stored default', () async {
      final settings = LayerSettings(FailingKeyValueStore());
      await settings.setStreetLabelsEnabled(false);
      // The write was swallowed, so the read falls back to the default —
      // the session-level toggle is the caller's to hold.
      expect(settings.streetLabelsEnabled, isTrue);
    });
  });
}
