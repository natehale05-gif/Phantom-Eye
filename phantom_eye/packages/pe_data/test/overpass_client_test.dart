import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pe_data/pe_data.dart';
import 'package:test/test.dart';

String _elements(List<Map<String, dynamic>> els) =>
    jsonEncode({'elements': els});

/// Routes by host so each mirror can be given its own behaviour.
MockClient _mirrors({
  required Future<http.Response> Function(http.Request) primary,
  required Future<http.Response> Function(http.Request) secondary,
  List<http.Request>? seen,
}) => MockClient((request) async {
  seen?.add(request);
  if (request.url.host == 'overpass-api.de') return primary(request);
  return secondary(request);
});

Future<http.Response> _ok(String body, {Duration? after}) async {
  if (after != null) await Future<void>.delayed(after);
  return http.Response(body, 200);
}

Future<http.Response> _status(int code, {Duration? after}) async {
  if (after != null) await Future<void>.delayed(after);
  return http.Response('boom', code);
}

Future<http.Response> _throw({Duration? after}) async {
  if (after != null) await Future<void>.delayed(after);
  throw http.ClientException('connection reset');
}

void main() {
  group('request construction', () {
    test('POSTs form-urlencoded data= to every mirror', () async {
      final seen = <http.Request>[];
      final client = OverpassClient(
        client: _mirrors(
          seen: seen,
          primary: (_) => _ok(_elements([])),
          secondary: (_) => _ok(_elements([])),
        ),
      );

      await client.query('[out:json];node["amenity"="cafe"];out;');

      expect(seen, isNotEmpty);
      final request = seen.first;
      expect(request.method, 'POST');
      expect(
        request.headers['Content-Type'],
        contains('application/x-www-form-urlencoded'),
      );
      // The body is the literal `data=` prefix plus the URL-encoded query,
      // matching the original rather than a generic form encoding.
      expect(request.body, startsWith('data='));
      expect(
        Uri.decodeQueryComponent(request.body.substring('data='.length)),
        '[out:json];node["amenity"="cafe"];out;',
      );
    });

    test('both mirrors are contacted, not tried in sequence', () async {
      final seen = <http.Request>[];
      final client = OverpassClient(
        client: _mirrors(
          seen: seen,
          // Slow so the second mirror definitely gets launched too.
          primary: (_) =>
              _ok(_elements([]), after: const Duration(milliseconds: 40)),
          secondary: (_) =>
              _ok(_elements([]), after: const Duration(milliseconds: 40)),
        ),
      );
      await client.query('test');
      expect(seen.map((r) => r.url.host).toSet(), {
        'overpass-api.de',
        'maps.mail.ru',
      });
    });

    test('the configured endpoint list is honoured', () async {
      final seen = <http.Request>[];
      final client = OverpassClient(
        endpoints: const ['https://example.test/interpreter'],
        client: MockClient((r) async {
          seen.add(r);
          return http.Response(_elements([]), 200);
        }),
      );
      await client.query('test');
      expect(seen.single.url.host, 'example.test');
    });
  });

  group('mirror racing', () {
    test('the faster mirror wins', () async {
      final client = OverpassClient(
        client: _mirrors(
          primary: (_) => _ok(
            _elements([
              {'id': 1},
            ]),
            after: const Duration(milliseconds: 60),
          ),
          secondary: (_) => _ok(
            _elements([
              {'id': 2},
              {'id': 3},
            ]),
            after: const Duration(milliseconds: 5),
          ),
        ),
      );
      final result = await client.query('test');
      expect(result!.length, 2, reason: 'the fast mirror\'s payload');
    });

    test(
      'a FAST 504 does not kill the request — the Future.any trap',
      () async {
        // This is the case the whole raceForFirstSuccess helper exists for.
        // Mirror racing was added precisely because these mirrors 504 often, so
        // a fast failure alongside a slower success is the COMMON case.
        final client = OverpassClient(
          client: _mirrors(
            primary: (_) =>
                _status(504, after: const Duration(milliseconds: 2)),
            secondary: (_) => _ok(
              _elements([
                {'id': 7},
              ]),
              after: const Duration(milliseconds: 40),
            ),
          ),
        );
        final result = await client.query('test');
        expect(result, isNotNull, reason: 'the slow mirror must still be used');
        expect(result!.elements.single['id'], 7);
      },
    );

    test('a transport error on one mirror is survivable too', () async {
      final client = OverpassClient(
        client: _mirrors(
          primary: (_) => _throw(after: const Duration(milliseconds: 2)),
          secondary: (_) => _ok(
            _elements([
              {'id': 9},
            ]),
          ),
        ),
      );
      final result = await client.query('test');
      expect(result!.elements.single['id'], 9);
    });

    test('non-2xx counts as a mirror failure, not a global one', () async {
      for (final code in [400, 429, 500, 504]) {
        final client = OverpassClient(
          client: _mirrors(
            primary: (_) => _status(code),
            secondary: (_) => _ok(
              _elements([
                {'ok': true},
              ]),
            ),
          ),
        );
        expect(await client.query('test'), isNotNull, reason: 'status $code');
      }
    });

    test('null only when EVERY mirror fails', () async {
      final client = OverpassClient(
        client: _mirrors(
          primary: (_) => _status(504),
          secondary: (_) => _throw(),
        ),
      );
      expect(await client.query('test'), isNull);
    });

    test('all mirrors failing returns null rather than throwing', () async {
      // The legacy contract: callers treat null as "no data this time" and
      // retry on the next settle, so this must never surface as an error.
      final client = OverpassClient(
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      await expectLater(client.query('test'), completion(isNull));
    });

    test('a hung mirror times out and the other wins', () async {
      final client = OverpassClient(
        timeout: const Duration(milliseconds: 80),
        client: _mirrors(
          primary: (_) =>
              _ok(_elements([]), after: const Duration(seconds: 30)),
          secondary: (_) => _ok(
            _elements([
              {'id': 5},
            ]),
            after: const Duration(milliseconds: 10),
          ),
        ),
      );
      final result = await client.query('test');
      expect(result!.elements.single['id'], 5);
    });

    test('both hanging past the timeout yields null', () async {
      final client = OverpassClient(
        timeout: const Duration(milliseconds: 30),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return http.Response(_elements([]), 200);
        }),
      );
      expect(await client.query('test'), isNull);
    });
  });

  group('decoding', () {
    test('reads the elements array', () async {
      final client = OverpassClient(
        client: MockClient(
          (_) async => http.Response(
            _elements([
              {
                'type': 'node',
                'id': 1,
                'tags': {'name': 'Cafe'},
              },
              {'type': 'way', 'id': 2},
            ]),
            200,
          ),
        ),
      );
      final r = await client.query('test');
      expect(r!.length, 2);
      expect(r.elements.first['tags'], {'name': 'Cafe'});
    });

    test(
      'an empty elements array is a successful empty result, not null',
      () async {
        final client = OverpassClient(
          client: MockClient((_) async => http.Response(_elements([]), 200)),
        );
        final r = await client.query('test');
        expect(r, isNotNull);
        expect(r!.isEmpty, isTrue);
      },
    );

    test('non-object entries are dropped', () async {
      final client = OverpassClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'elements': [
                {'id': 1},
                'junk',
                42,
                null,
              ],
            }),
            200,
          ),
        ),
      );
      final r = await client.query('test');
      expect(r!.length, 1);
    });

    test('malformed JSON surfaces as a failure of that mirror', () async {
      // The primary returns garbage; the secondary should still carry it.
      final client = OverpassClient(
        client: _mirrors(
          primary: (_) => _ok('not json at all'),
          secondary: (_) => _ok(
            _elements([
              {'id': 3},
            ]),
            after: const Duration(milliseconds: 20),
          ),
        ),
      );
      // Decoding happens inside each attempt, so garbage from a FAST mirror
      // counts as that mirror failing and the slower good one still wins.
      // Decoding after the race instead would let the garbage take the win
      // and then throw out of query(), breaking the never-throws contract.
      final r = await client.query('test');
      expect(r, isNotNull, reason: 'the good mirror must still carry it');
      expect(r!.elements.single['id'], 3);
    });

    test(
      'malformed JSON from every mirror yields null, never a throw',
      () async {
        final client = OverpassClient(
          client: MockClient(
            (_) async => http.Response('<html>502</html>', 200),
          ),
        );
        await expectLater(client.query('test'), completion(isNull));
      },
    );

    test('a JSON array instead of an object is a mirror failure', () async {
      // Some error pages answer 200 with valid-but-wrong JSON.
      final client = OverpassClient(
        client: _mirrors(
          primary: (_) => _ok('[1,2,3]'),
          secondary: (_) => _ok(
            _elements([
              {'id': 4},
            ]),
            after: const Duration(milliseconds: 20),
          ),
        ),
      );
      final r = await client.query('test');
      expect(r!.elements.single['id'], 4);
    });

    test('a response without an elements key yields null', () async {
      final client = OverpassClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'version': 0.6}), 200),
        ),
      );
      expect(await client.query('test'), isNull);
    });
  });
}
