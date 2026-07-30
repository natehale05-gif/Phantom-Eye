import 'package:pe_core/pe_core.dart';
import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

const _near = LngLat(-123.262, 44.5646);

final _coffee = categoryById('coffee')!;
final _food = categoryById('food')!;

/// A node element at an offset from [_near], in metres east.
Map<String, dynamic> _node(
  int id,
  String name, {
  double metresEast = 100,
  Map<String, String> tags = const {},
}) {
  final at = destinationPoint(_near, 90, metresEast);
  return {
    'type': 'node',
    'id': id,
    'lat': at.lat,
    'lon': at.lon,
    'tags': {'name': name, ...tags},
  };
}

Map<String, dynamic> _way(
  int id,
  String name, {
  double metresEast = 100,
  Map<String, String> tags = const {},
}) {
  final at = destinationPoint(_near, 90, metresEast);
  return {
    'type': 'way',
    'id': id,
    'center': {'lat': at.lat, 'lon': at.lon},
    'tags': {'name': name, ...tags},
  };
}

void main() {
  group('buildNearbyQuery', () {
    test('emits a node and a way clause per tag pair', () {
      final q = buildNearbyQuery(_coffee, _near);
      for (final tag in _coffee.osmTags) {
        expect(q, contains('node["${tag.key}"="${tag.value}"]'));
        expect(q, contains('way["${tag.key}"="${tag.value}"]'));
      }
      expect(
        q,
        isNot(contains('relation[')),
        reason:
            'relations are deliberately not queried — too few POIs use them '
            'to justify the recursion cost on a public mirror',
      );
    });

    test('uses the documented radius, timeout and output limit', () {
      final q = buildNearbyQuery(_food, _near);
      expect(q, contains('around:3000,44.5646,-123.262'));
      expect(q, startsWith('[out:json][timeout:20];'));
      // `out center` is what gives way results a coordinate at all.
      expect(q, endsWith('out center 54;'));
      expect(kNearbyOverpassLimit, kNearbyMaxResults * 3);
    });

    test('the clause list is wrapped in a union group', () {
      final q = buildNearbyQuery(_coffee, _near);
      expect(q, contains('(node['));
      expect(q, contains(');out center'));
    });
  });

  group('buildPlaceDetailsQuery', () {
    test('spells the OSM type out in full, as Overpass requires', () {
      expect(
        buildPlaceDetailsQuery(OsmType.way, 123456),
        '[out:json][timeout:15];way(123456);out tags;',
      );
      expect(buildPlaceDetailsQuery(OsmType.node, 7), contains('node(7);'));
      expect(
        buildPlaceDetailsQuery(OsmType.relation, 9),
        contains('relation(9);'),
      );
    });
  });

  group('placeFromOverpassElement', () {
    test('maps a node', () {
      final place = placeFromOverpassElement(
        _node(1, 'Interzone', tags: const {'cuisine': 'coffee_shop'}),
        category: _coffee,
      )!;
      expect(place.name, 'Interzone');
      expect(place.osmType, OsmType.node);
      expect(place.osmId, 1);
      expect(place.category, _coffee.label);
      expect(place.categoryId, 'coffee');
    });

    test(
      'a way takes its coordinate from center, which out center supplies',
      () {
        final place = placeFromOverpassElement(
          _way(2, 'Cafe'),
          category: _coffee,
        )!;
        expect(place.position.lat, closeTo(44.5646, 1e-6));
        expect(place.osmType, OsmType.way);
      },
    );

    test('center wins over lat/lon when both are present', () {
      final element = _way(3, 'Cafe', metresEast: 500);
      element['lat'] = 0.0;
      element['lon'] = 0.0;
      final place = placeFromOverpassElement(element, category: _coffee)!;
      expect(place.position.lat, closeTo(44.5646, 1e-6));
    });

    test('an unnamed element is dropped — you cannot navigate to it', () {
      final element = _node(4, 'x')..['tags'] = <String, String>{};
      expect(placeFromOverpassElement(element, category: _coffee), isNull);
    });

    test('an element with no coordinate at all is dropped', () {
      expect(
        placeFromOverpassElement({
          'type': 'way',
          'id': 5,
          'tags': {'name': 'No geometry'},
        }, category: _coffee),
        isNull,
      );
    });

    test('non-string tag values are ignored rather than crashing', () {
      final place = placeFromOverpassElement({
        'type': 'node',
        'id': 6,
        'lat': 44.5,
        'lon': -123.2,
        'tags': {'name': 'Ok', 'level': 2, 'building': null},
      }, category: _coffee);
      expect(place!.name, 'Ok');
    });
  });

  group('overpassDetailLine', () {
    test('street, city and cuisine, capped at two parts', () {
      expect(
        overpassDetailLine(const {
          'addr:housenumber': '300',
          'addr:street': 'SW Jefferson Ave',
          'addr:city': 'Corvallis',
          'cuisine': 'coffee_shop',
        }),
        '300 SW Jefferson Ave · Corvallis',
      );
    });

    test('cuisine underscores become spaces', () {
      expect(
        overpassDetailLine(const {'cuisine': 'coffee_shop'}),
        'coffee shop',
      );
    });

    test('cuisine reaches the line when the address is missing', () {
      expect(
        overpassDetailLine(const {
          'addr:city': 'Corvallis',
          'cuisine': 'pizza',
        }),
        'Corvallis · pizza',
      );
    });

    test('a housenumber with no street is not shown alone', () {
      expect(
        overpassDetailLine(const {
          'addr:housenumber': '300',
          'addr:city': 'Corvallis',
        }),
        'Corvallis',
      );
    });

    test('no usable tags yields an empty line', () {
      expect(overpassDetailLine(const {}), '');
    });
  });

  group('overpassDetails', () {
    test('reads contact tags in both the modern and contact: forms', () {
      expect(
        overpassDetails(const {'phone': '+1 541 555 0100'}).phone,
        '+1 541 555 0100',
      );
      expect(
        overpassDetails(const {'contact:phone': '+1 541 555 0101'}).phone,
        '+1 541 555 0101',
      );
      expect(
        overpassDetails(const {'website': 'https://a.test'}).website,
        'https://a.test',
      );
      expect(
        overpassDetails(const {'contact:website': 'https://b.test'}).website,
        'https://b.test',
      );
      expect(
        overpassDetails(const {'url': 'https://c.test'}).website,
        'https://c.test',
      );
    });

    test('the modern form wins over the contact: form', () {
      expect(
        overpassDetails(const {
          'phone': 'modern',
          'contact:phone': 'legacy',
        }).phone,
        'modern',
      );
    });

    test('builds the full address', () {
      expect(
        overpassDetails(const {
          'addr:housenumber': '300',
          'addr:street': 'SW Jefferson Ave',
          'addr:city': 'Corvallis',
          'addr:state': 'OR',
          'addr:postcode': '97333',
        }).address,
        '300 SW Jefferson Ave, Corvallis, OR, 97333',
      );
    });

    test('an empty address is null, not an empty string', () {
      final details = overpassDetails(const {
        'opening_hours': 'Mo-Fr 07:00-18:00',
      });
      expect(details.address, isNull);
      expect(details.openingHours, 'Mo-Fr 07:00-18:00');
    });

    test('no tags yields an empty details object', () {
      expect(overpassDetails(const {}).isEmpty, isTrue);
    });
  });

  group('rankNearbyResults', () {
    test('results come back nearest first', () {
      final places = rankNearbyResults(
        [
          _node(1, 'Far', metresEast: 2000),
          _node(2, 'Near', metresEast: 100),
          _node(3, 'Middle', metresEast: 800),
        ],
        category: _coffee,
        near: _near,
      );
      expect(places.map((p) => p.name), ['Near', 'Middle', 'Far']);
    });

    test('REGRESSION: distinct branches sharing a name all survive', () {
      // The original deduped on the lowercased name while streaming
      // elements in, so searching "coffee" in a city returned a single
      // Starbucks instead of the four around you.
      final places = rankNearbyResults(
        [
          _node(1, 'Starbucks', metresEast: 1500),
          _node(2, 'Starbucks', metresEast: 300),
          _node(3, 'Starbucks', metresEast: 900),
        ],
        category: _coffee,
        near: _near,
      );
      expect(places, hasLength(3));
      expect(places.map((p) => p.osmId), [
        2,
        3,
        1,
      ], reason: 'and they are ordered by distance');
    });

    test(
      'REGRESSION: when a duplicate IS collapsed, the nearest copy survives',
      () {
        // Because the original deduped before sorting, the survivor was
        // whichever Overpass emitted first — element-id order, not distance.
        // Sorting afterwards could not undo that: the nearer copy was gone.
        final places = rankNearbyResults(
          [
            // Emitted first, but further away.
            _node(1, 'Dutch Bros', metresEast: 2000),
            _node(2, 'Dutch Bros', metresEast: 120),
          ],
          category: _coffee,
          near: _near,
        );
        expect(places, hasLength(2), reason: '2 km apart is two shops');

        // Genuinely co-located: the same POI as a node and as its building.
        final collapsed = rankNearbyResults(
          [
            _way(10, 'Dutch Bros', metresEast: 2000),
            _node(11, 'Dutch Bros', metresEast: 2010),
          ],
          category: _coffee,
          near: _near,
        );
        expect(collapsed, hasLength(1));
        expect(collapsed.single.osmId, 10, reason: 'the nearer of the pair');
      },
    );

    test('the same element repeated is collapsed by OSM identity', () {
      final element = _node(42, 'Interzone');
      final places = rankNearbyResults(
        [element, element],
        category: _coffee,
        near: _near,
      );
      expect(places, hasLength(1));
    });

    test('a node and a way with the same id are NOT the same place', () {
      // OSM ids are only unique per type, so the type has to be part of the
      // dedupe key.
      final places = rankNearbyResults(
        [_node(7, 'A'), _way(7, 'B', metresEast: 400)],
        category: _coffee,
        near: _near,
      );
      expect(places, hasLength(2));
    });

    test('same name just outside the collapse radius is kept', () {
      final places = rankNearbyResults(
        [
          _node(1, 'Cafe', metresEast: 100),
          _node(2, 'Cafe', metresEast: 100 + kNearbyDuplicateMeters + 20),
        ],
        category: _coffee,
        near: _near,
      );
      expect(places, hasLength(2));
    });

    test('the collapse is name-sensitive, not purely positional', () {
      // Two different shops in the same building must both be listed.
      final places = rankNearbyResults(
        [
          _node(1, 'Cafe A', metresEast: 100),
          _node(2, 'Cafe B', metresEast: 105),
        ],
        category: _coffee,
        near: _near,
      );
      expect(places, hasLength(2));
    });

    test('the list is capped', () {
      final places = rankNearbyResults(
        [
          for (var i = 0; i < 60; i++)
            _node(i, 'Shop $i', metresEast: 100 + i * 30),
        ],
        category: _coffee,
        near: _near,
      );
      expect(places, hasLength(kNearbyMaxResults));
      expect(places.first.name, 'Shop 0', reason: 'the cap keeps the nearest');
    });

    test('the cap is overridable for tests and other surfaces', () {
      final places = rankNearbyResults(
        [for (var i = 0; i < 10; i++) _node(i, 'Shop $i')],
        category: _coffee,
        near: _near,
        maxResults: 3,
      );
      expect(places, hasLength(3));
    });

    test('unusable elements are skipped without disturbing the order', () {
      final places = rankNearbyResults(
        [
          {'type': 'node', 'id': 1},
          _node(2, 'Near', metresEast: 100),
          {'type': 'way', 'id': 3, 'tags': <String, String>{}},
          _node(4, 'Far', metresEast: 900),
        ],
        category: _coffee,
        near: _near,
      );
      expect(places.map((p) => p.name), ['Near', 'Far']);
    });

    test('an empty response yields an empty list', () {
      expect(
        rankNearbyResults(const [], category: _coffee, near: _near),
        isEmpty,
      );
    });

    test('every result carries the searched category', () {
      final places = rankNearbyResults(
        [_node(1, 'Interzone')],
        category: _coffee,
        near: _near,
      );
      expect(places.single.categoryId, 'coffee');
      expect(places.single.category, _coffee.label);
    });
  });
}
