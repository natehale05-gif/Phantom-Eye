import 'package:pe_core/pe_core.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryKeyValueStore', () {
    test('reads back what was written', () async {
      final store = InMemoryKeyValueStore();
      expect(store.read('a'), isNull);
      await store.write('a', '1');
      expect(store.read('a'), '1');
      await store.write('a', '2');
      expect(store.read('a'), '2');
      await store.remove('a');
      expect(store.read('a'), isNull);
    });

    test('removing an absent key is a no-op', () async {
      final store = InMemoryKeyValueStore();
      await store.remove('nope');
      expect(store.entries, isEmpty);
    });

    test('a seed populates it', () {
      final store = InMemoryKeyValueStore({'a': '1', 'b': '2'});
      expect(store.read('a'), '1');
      expect(store.entries, hasLength(2));
    });

    test('the seed map is copied, not aliased', () async {
      final seed = {'a': '1'};
      final store = InMemoryKeyValueStore(seed);
      await store.write('b', '2');
      expect(seed, hasLength(1), reason: 'the caller\'s map is untouched');
    });

    test('entries is a read-only snapshot', () {
      final store = InMemoryKeyValueStore({'a': '1'});
      expect(() => store.entries['b'] = '2', throwsUnsupportedError);
    });

    test('reads are synchronous, so a render path never awaits', () {
      // The interface is deliberately sync-read/async-write: a place card asks
      // for a saved price while building its widget, and an await there would
      // mean a frame with the price missing.
      final String? value = InMemoryKeyValueStore({'a': '1'}).read('a');
      expect(value, '1');
    });
  });

  group('FailingKeyValueStore', () {
    test('writes throw but reads still work', () async {
      final store = FailingKeyValueStore({'a': '1'});
      expect(store.read('a'), '1');
      await expectLater(store.write('a', '2'), throwsStateError);
      await expectLater(store.remove('a'), throwsStateError);
      expect(store.read('a'), '1', reason: 'unchanged');
    });
  });

  group('StorageKeys', () {
    test('match the legacy app byte for byte', () {
      // A future migration can only read the old data if these are identical.
      expect(StorageKeys.waypoints, 'phantom-eye.waypoints');
      expect(StorageKeys.gasPrices, 'phantom-eye.gasPrices');
      expect(StorageKeys.recents, 'phantom-eye.recents');
      expect(StorageKeys.streetLabels, 'nomos:labels');
      expect(StorageKeys.trailLayer('bike'), 'nomos:trail:bike');
      expect(StorageKeys.trailLayer('offroad'), 'nomos:trail:offroad');
    });

    test('every key is distinct', () {
      final keys = {
        StorageKeys.waypoints,
        StorageKeys.gasPrices,
        StorageKeys.recents,
        StorageKeys.streetLabels,
        StorageKeys.trailLayer('a'),
        StorageKeys.trailLayer('b'),
      };
      expect(keys, hasLength(6));
    });
  });

  group('Place JSON', () {
    test('round-trips through the flat legacy shape', () {
      const place = Place(
        name: 'Block 15',
        detail: 'Corvallis',
        position: LngLat(-123.262, 44.5646),
        category: 'pub',
        categoryId: 'food',
        osmType: OsmType.way,
        osmId: 99,
        details: PlaceDetails(phone: '+1', address: '300 SW Jefferson Ave'),
      );
      final json = place.toJson();
      // PlaceResult extended PlaceDetails in the original, so the detail
      // fields sit alongside the rest rather than nested.
      expect(json['lon'], -123.262);
      expect(json['osmType'], 'way');
      expect(json['phone'], '+1');
      expect(json.containsKey('details'), isFalse);
      expect(
        json.containsKey('website'),
        isFalse,
        reason: 'absent stays absent',
      );

      final back = Place.fromJson(json)!;
      expect(back.name, 'Block 15');
      expect(back.osmType, OsmType.way);
      expect(back.osmId, 99);
      expect(back.details.phone, '+1');
      expect(back.details.address, '300 SW Jefferson Ave');
      expect(back.details.website, isNull);
    });

    test('unusable entries yield null', () {
      expect(Place.fromJson(null), isNull);
      expect(Place.fromJson('nope'), isNull);
      expect(Place.fromJson(const {}), isNull);
      expect(Place.fromJson({'name': 'X'}), isNull, reason: 'no coordinate');
      expect(Place.fromJson({'lon': 1, 'lat': 2}), isNull, reason: 'no name');
      expect(
        Place.fromJson({'name': '', 'lon': 1, 'lat': 2}),
        isNull,
        reason: 'empty name',
      );
      expect(
        Place.fromJson({'name': 'X', 'lon': double.infinity, 'lat': 2}),
        isNull,
      );
    });

    test('an unknown osmType is dropped rather than guessed', () {
      final place = Place.fromJson({
        'name': 'X',
        'lon': 1,
        'lat': 2,
        'osmType': 'galaxy',
      })!;
      expect(place.osmType, isNull);
      expect(place.osmKey, isNull);
    });
  });

  group('OsmType', () {
    test('parses both the Overpass and Photon spellings', () {
      expect(OsmType.parse('node'), OsmType.node);
      expect(OsmType.parse('N'), OsmType.node);
      expect(OsmType.parse('way'), OsmType.way);
      expect(OsmType.parse('W'), OsmType.way);
      expect(OsmType.parse('relation'), OsmType.relation);
      expect(OsmType.parse('R'), OsmType.relation);
    });

    test('anything else is null', () {
      expect(OsmType.parse(null), isNull);
      expect(OsmType.parse(''), isNull);
      expect(OsmType.parse('n'), isNull, reason: 'case matters');
      expect(OsmType.parse(42), isNull);
    });
  });

  group('PlaceDetails.merge', () {
    test('a lazily-fetched lookup does not erase what search already knew', () {
      const known = PlaceDetails(phone: '+1', address: 'Main St');
      const fetched = PlaceDetails(website: 'https://a.test', phone: '+2');
      final merged = known.merge(fetched);
      expect(merged.phone, '+2', reason: 'the fresher value wins');
      expect(merged.website, 'https://a.test');
      expect(merged.address, 'Main St', reason: 'not erased by a null');
    });

    test('merging an empty lookup changes nothing', () {
      const known = PlaceDetails(phone: '+1');
      final merged = known.merge(const PlaceDetails());
      expect(merged.phone, '+1');
      expect(const PlaceDetails().isEmpty, isTrue);
    });
  });
}
