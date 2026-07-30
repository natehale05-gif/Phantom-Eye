import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pe_core/pe_core.dart';
import 'package:pe_data/pe_data.dart';
import 'package:test/test.dart';

Map<String, dynamic> _feature(
  Map<String, dynamic> properties, {
  double lon = -123.262,
  double lat = 44.5646,
}) => {
  'geometry': {
    'type': 'Point',
    'coordinates': [lon, lat],
  },
  'properties': properties,
};

String _body(List<Map<String, dynamic>> features) =>
    jsonEncode({'type': 'FeatureCollection', 'features': features});

void main() {
  group('photonDisplayName', () {
    test('a POI uses its name', () {
      expect(photonDisplayName({'name': 'Block 15'}), 'Block 15');
    });

    test('an address uses housenumber + street', () {
      expect(
        photonDisplayName({'housenumber': '300', 'street': 'SW Jefferson Ave'}),
        '300 SW Jefferson Ave',
      );
    });

    test('a street with no housenumber uses the bare street', () {
      expect(
        photonDisplayName({'street': 'SW Jefferson Ave'}),
        'SW Jefferson Ave',
      );
    });

    test('falls back city then state then country', () {
      expect(photonDisplayName({'city': 'Corvallis'}), 'Corvallis');
      expect(photonDisplayName({'state': 'Oregon'}), 'Oregon');
      expect(photonDisplayName({'country': 'United States'}), 'United States');
    });

    test('an unusable feature yields empty, which drops the row', () {
      expect(photonDisplayName(const {}), '');
      expect(photonDisplayName({'postcode': '97333'}), '');
    });
  });

  group('photonAddressLine', () {
    test('street plus city line', () {
      expect(
        photonAddressLine({
          'housenumber': '300',
          'street': 'SW Jefferson Ave',
          'city': 'Corvallis',
          'state': 'Oregon',
          'postcode': '97333',
        }),
        '300 SW Jefferson Ave, Corvallis, Oregon, 97333',
      );
    });

    test('locality stands in for a missing city', () {
      expect(
        photonAddressLine({'street': 'Main St', 'locality': 'Philomath'}),
        'Main St, Philomath',
      );
    });

    test('a housenumber with no street is dropped, not shown alone', () {
      // Guards the `housenumber && street` condition: emitting a bare "300"
      // as the street line would read as nonsense.
      expect(
        photonAddressLine({'housenumber': '300', 'city': 'Corvallis'}),
        'Corvallis',
      );
    });

    test('nothing usable yields empty', () {
      expect(photonAddressLine(const {}), '');
    });
  });

  group('photonDetailLine', () {
    test('parts that merely repeat the name are suppressed', () {
      // Searching a city must not render "Corvallis / Corvallis, Oregon".
      expect(
        photonDetailLine({'city': 'Corvallis', 'state': 'Oregon'}, 'Corvallis'),
        'Oregon',
      );
    });

    test('state is suppressed when it equals the town too', () {
      // A city-state such as Singapore or Berlin, where Photon reports the
      // same string in both fields.
      expect(
        photonDetailLine({
          'city': 'Berlin',
          'state': 'Berlin',
        }, 'Brandenburg Gate'),
        'Berlin',
      );
    });

    test('country appears only when everything else was suppressed', () {
      expect(
        photonDetailLine({
          'city': 'Corvallis',
          'country': 'United States',
        }, 'Corvallis'),
        'United States',
      );
      expect(
        photonDetailLine({
          'city': 'Corvallis',
          'country': 'United States',
        }, 'Block 15'),
        'Corvallis',
      );
    });

    test('county stands in when city and locality are absent', () {
      expect(
        photonDetailLine({'county': 'Benton County'}, 'Bald Hill'),
        'Benton County',
      );
    });

    test('street line is shown when it differs from the name', () {
      expect(
        photonDetailLine({
          'housenumber': '300',
          'street': 'SW Jefferson Ave',
          'city': 'Corvallis',
        }, 'Block 15'),
        '300 SW Jefferson Ave, Corvallis',
      );
    });
  });

  group('parsePhotonSearch', () {
    test('maps a full feature field by field', () {
      final places = parsePhotonSearch(
        jsonDecode(
              _body([
                _feature({
                  'name': 'Block 15 Brewing',
                  'housenumber': '300',
                  'street': 'SW Jefferson Ave',
                  'city': 'Corvallis',
                  'state': 'Oregon',
                  'postcode': '97333',
                  'country': 'United States',
                  'osm_key': 'amenity',
                  'osm_value': 'pub',
                  'osm_type': 'W',
                  'osm_id': 123456,
                }),
              ]),
            )
            as Map<String, dynamic>,
      );

      expect(places, hasLength(1));
      final p = places.single;
      expect(p.name, 'Block 15 Brewing');
      expect(p.detail, '300 SW Jefferson Ave, Corvallis, Oregon');
      expect(p.position, const LngLat(-123.262, 44.5646));
      // osm_value beats osm_key, so the specific kind wins over the namespace.
      expect(p.category, 'pub');
      expect(p.osmType, OsmType.way);
      expect(p.osmId, 123456);
      expect(
        p.details.address,
        '300 SW Jefferson Ave, Corvallis, Oregon, 97333',
      );
      expect(p.osmKey, 'way/123456');
    });

    test('osm_key is used when osm_value is absent', () {
      final places = parsePhotonSearch({
        'features': [
          _feature({'name': 'Somewhere', 'osm_key': 'tourism'}),
        ],
      });
      expect(places.single.category, 'tourism');
    });

    test('all three Photon osm_type letters are understood', () {
      for (final (letter, expected) in [
        ('N', OsmType.node),
        ('W', OsmType.way),
        ('R', OsmType.relation),
      ]) {
        final places = parsePhotonSearch({
          'features': [
            _feature({'name': 'X', 'osm_type': letter}),
          ],
        });
        expect(places.single.osmType, expected, reason: letter);
      }
    });

    test('dedupes on name plus coordinates rounded to 4dp', () {
      // Photon returns the same POI as a node and a way; ~11 m apart at 4dp
      // they collapse. Exact coordinate equality would never have fired.
      final places = parsePhotonSearch({
        'features': [
          _feature({'name': 'Block 15'}, lon: -123.26200, lat: 44.56460),
          _feature({'name': 'Block 15'}, lon: -123.262001, lat: 44.564602),
        ],
      });
      expect(places, hasLength(1));
    });

    test('same name far apart is kept — two branches are two places', () {
      final places = parsePhotonSearch({
        'features': [
          _feature({'name': 'Starbucks'}, lon: -123.262, lat: 44.5646),
          _feature({'name': 'Starbucks'}, lon: -123.280, lat: 44.5700),
        ],
      });
      expect(places, hasLength(2));
    });

    test('features with no name and nothing to fall back to are dropped', () {
      final places = parsePhotonSearch({
        'features': [
          _feature({'postcode': '97333'}),
          _feature({'name': 'Kept'}),
        ],
      });
      expect(places.map((p) => p.name), ['Kept']);
    });

    test('features with unusable geometry are dropped', () {
      final places = parsePhotonSearch({
        'features': [
          {
            'geometry': {'coordinates': <double>[]},
            'properties': {'name': 'No coords'},
          },
          {
            'properties': {'name': 'No geometry'},
          },
          {
            'geometry': {
              'coordinates': ['x', 'y'],
            },
            'properties': {'name': 'Non-numeric'},
          },
          _feature({'name': 'Kept'}),
        ],
      });
      expect(places.map((p) => p.name), ['Kept']);
    });

    test('a response with no features array yields an empty list', () {
      expect(parsePhotonSearch(const {}), isEmpty);
      expect(parsePhotonSearch({'features': 'nope'}), isEmpty);
    });

    test('an empty address becomes null rather than an empty string', () {
      final places = parsePhotonSearch({
        'features': [
          _feature({'name': 'Bald Hill'}),
        ],
      });
      expect(places.single.details.address, isNull);
      expect(places.single.details.isEmpty, isTrue);
    });
  });

  group('parsePhotonReverseName', () {
    test('city wins', () {
      expect(
        parsePhotonReverseName({
          'features': [
            _feature({
              'city': 'Corvallis',
              'name': 'Block 15',
              'state': 'Oregon',
            }),
          ],
        }),
        'Corvallis',
      );
    });

    test('a settlement-typed feature contributes its name', () {
      for (final type in kPhotonPlaceTypes) {
        expect(
          parsePhotonReverseName({
            'features': [
              _feature({'name': 'Philomath', 'type': type}),
            ],
          }),
          'Philomath',
          reason: type,
        );
      }
    });

    test('a non-settlement name still wins over county and state', () {
      // The `type` gate only controls *precedence*; a bare name is still
      // better than falling all the way back to the state.
      expect(
        parsePhotonReverseName({
          'features': [
            _feature({
              'name': 'Block 15 Brewing',
              'type': 'house',
              'county': 'Benton County',
            }),
          ],
        }),
        'Block 15 Brewing',
      );
    });

    test('county then state are the last resorts', () {
      expect(
        parsePhotonReverseName({
          'features': [
            _feature({'county': 'Benton County', 'state': 'Oregon'}),
          ],
        }),
        'Benton County',
      );
      expect(
        parsePhotonReverseName({
          'features': [
            _feature({'state': 'Oregon'}),
          ],
        }),
        'Oregon',
      );
    });

    test('nothing usable yields null so the caller can fall through', () {
      expect(parsePhotonReverseName(const {}), isNull);
      expect(parsePhotonReverseName({'features': <Object>[]}), isNull);
      expect(
        parsePhotonReverseName({
          'features': [_feature(const {})],
        }),
        isNull,
      );
    });
  });

  group('PhotonClient.search', () {
    test('sends q, limit and lang, and no bias without a location', () async {
      Uri? seen;
      final client = PhotonClient(
        client: MockClient((r) async {
          seen = r.url;
          return http.Response(_body(const []), 200);
        }),
      );
      await client.search('  coffee  ');

      expect(seen!.queryParameters['q'], 'coffee', reason: 'trimmed');
      expect(seen!.queryParameters['limit'], '7');
      expect(seen!.queryParameters['lang'], 'en');
      expect(seen!.queryParameters.containsKey('lat'), isFalse);
      expect(seen!.queryParameters.containsKey('lon'), isFalse);
    });

    test('biases toward a location when given one', () async {
      Uri? seen;
      final client = PhotonClient(
        client: MockClient((r) async {
          seen = r.url;
          return http.Response(_body(const []), 200);
        }),
      );
      await client.search('coffee', near: const LngLat(-123.262, 44.5646));
      expect(seen!.queryParameters['lat'], '44.5646');
      expect(seen!.queryParameters['lon'], '-123.262');
    });

    test('a query under two characters is not sent at all', () async {
      var calls = 0;
      final client = PhotonClient(
        client: MockClient((_) async {
          calls++;
          return http.Response(_body(const []), 200);
        }),
      );
      expect(await client.search('a'), isEmpty);
      expect(await client.search('  '), isEmpty);
      expect(await client.search(''), isEmpty);
      expect(calls, 0, reason: 'this runs on every keystroke');
    });

    test('non-200 throws with the status in the message', () async {
      final client = PhotonClient(
        client: MockClient((_) async => http.Response('gone', 503)),
      );
      await expectLater(
        client.search('coffee'),
        throwsA(
          isA<SearchException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.message, 'message', contains('503')),
        ),
      );
    });

    test(
      'an HTML error page surfaces as SearchException, not FormatException',
      () async {
        final client = PhotonClient(
          client: MockClient(
            (_) async => http.Response('<html>502</html>', 200),
          ),
        );
        await expectLater(
          client.search('coffee'),
          throwsA(isA<SearchException>()),
        );
      },
    );

    test('a JSON array body surfaces as SearchException', () async {
      final client = PhotonClient(
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      await expectLater(
        client.search('coffee'),
        throwsA(isA<SearchException>()),
      );
    });

    test('a transport error surfaces as SearchException', () async {
      final client = PhotonClient(
        client: MockClient((_) async => throw http.ClientException('reset')),
      );
      await expectLater(
        client.search('coffee'),
        throwsA(isA<SearchException>()),
      );
    });

    test(
      'non-ASCII names survive as UTF-8 regardless of the charset header',
      () async {
        // Photon sometimes omits the charset, which would have http decode the
        // body as Latin-1 and turn Köln into KÃ¶ln.
        final bytes = utf8.encode(
          _body([
            _feature({'name': 'Köln'}),
          ]),
        );
        final client = PhotonClient(
          client: MockClient.streaming(
            (_, _) async => http.StreamedResponse(
              Stream.value(bytes),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
        );
        final places = await client.search('koln');
        expect(places.single.name, 'Köln');
      },
    );
  });

  group('PhotonClient.reverseName', () {
    test('returns the resolved name', () async {
      final client = PhotonClient(
        client: MockClient(
          (_) async => http.Response(
            _body([
              _feature({'city': 'Corvallis'}),
            ]),
            200,
          ),
        ),
      );
      expect(
        await client.reverseName(const LngLat(-123.262, 44.5646)),
        'Corvallis',
      );
    });

    test('sends lon and lat', () async {
      Uri? seen;
      final client = PhotonClient(
        client: MockClient((r) async {
          seen = r.url;
          return http.Response(_body(const []), 200);
        }),
      );
      await client.reverseName(const LngLat(-123.262, 44.5646));
      expect(seen!.queryParameters['lon'], '-123.262');
      expect(seen!.queryParameters['lat'], '44.5646');
    });

    test('never throws — every failure mode yields null', () async {
      final failures = <MockClient>[
        MockClient((_) async => http.Response('nope', 500)),
        MockClient((_) async => http.Response('not json', 200)),
        MockClient((_) async => http.Response('[]', 200)),
        MockClient((_) async => throw http.ClientException('reset')),
      ];
      for (final mock in failures) {
        final client = PhotonClient(client: mock);
        expect(await client.reverseName(const LngLat(0, 0)), isNull);
      }
    });
  });

  group('parseBigDataCloudName', () {
    test('locality beats city, because city snaps to the wrong town', () {
      // BigDataCloud reports "Albany" as the city for Corvallis; locality is
      // the granular field and must win.
      expect(
        parseBigDataCloudName({'locality': 'Corvallis', 'city': 'Albany'}),
        'Corvallis',
      );
    });

    test('falls back city then subdivision then country', () {
      expect(parseBigDataCloudName({'city': 'Albany'}), 'Albany');
      expect(
        parseBigDataCloudName({'principalSubdivision': 'Oregon'}),
        'Oregon',
      );
      expect(
        parseBigDataCloudName({'countryName': 'United States'}),
        'United States',
      );
    });

    test('empty strings count as absent', () {
      expect(
        parseBigDataCloudName({'locality': '', 'city': 'Albany'}),
        'Albany',
      );
      expect(parseBigDataCloudName(const {}), isNull);
    });
  });

  group('ReverseGeocoder', () {
    test(
      'Photon wins when it answers, and BigDataCloud is never called',
      () async {
        final hosts = <String>[];
        final client = ReverseGeocoder(
          client: MockClient((r) async {
            hosts.add(r.url.host);
            if (r.url.host == 'photon.komoot.io') {
              return http.Response(
                _body([
                  _feature({'city': 'Corvallis'}),
                ]),
                200,
              );
            }
            return http.Response(jsonEncode({'locality': 'Albany'}), 200);
          }),
        );

        expect(
          await client.nameFor(const LngLat(-123.262, 44.5646)),
          'Corvallis',
        );
        expect(
          hosts,
          ['photon.komoot.io'],
          reason: 'the providers are sequential, not raced — Photon is better',
        );
      },
    );

    test('falls back to BigDataCloud when Photon fails', () async {
      final client = ReverseGeocoder(
        client: MockClient((r) async {
          if (r.url.host == 'photon.komoot.io') {
            return http.Response('boom', 500);
          }
          return http.Response(jsonEncode({'locality': 'Corvallis'}), 200);
        }),
      );
      expect(await client.nameFor(const LngLat(0, 0)), 'Corvallis');
    });

    test('sends the documented BigDataCloud parameters', () async {
      Uri? seen;
      final client = ReverseGeocoder(
        client: MockClient((r) async {
          if (r.url.host == 'photon.komoot.io') {
            return http.Response('boom', 500);
          }
          seen = r.url;
          return http.Response(jsonEncode({'locality': 'X'}), 200);
        }),
      );
      await client.nameFor(const LngLat(-123.262, 44.5646));
      expect(seen!.queryParameters['latitude'], '44.5646');
      expect(seen!.queryParameters['longitude'], '-123.262');
      expect(seen!.queryParameters['localityLanguage'], 'en');
    });

    test(
      'both failing yields the Current Location literal, never a throw',
      () async {
        final client = ReverseGeocoder(
          client: MockClient((_) async => http.Response('boom', 500)),
        );
        await expectLater(
          client.nameFor(const LngLat(0, 0)),
          completion(kUnknownPlaceName),
        );
        expect(kUnknownPlaceName, 'Current Location');
      },
    );

    test('a BigDataCloud transport error still yields the literal', () async {
      final client = ReverseGeocoder(
        client: MockClient((_) async => throw http.ClientException('reset')),
      );
      expect(await client.nameFor(const LngLat(0, 0)), kUnknownPlaceName);
    });
  });
}
