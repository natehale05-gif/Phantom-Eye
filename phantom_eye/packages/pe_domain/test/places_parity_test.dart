@Tags(['parity'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

/// Cross-checks the curated place table against the legacy TypeScript.
///
/// `test/fixtures/places_reference.json` is produced by
/// `tool/gen_places_fixture.mjs`, which compiles and imports the real
/// `src/places.ts`. The camera framings are hand-tuned and not derivable from
/// the coordinate, so a one-digit slip in a heading or pitch would silently
/// ruin one destination's arrival shot — exactly the kind of error a
/// hand-written expectation accepts without complaint.
void main() {
  final file = File('test/fixtures/places_reference.json');
  if (!file.existsSync()) {
    throw StateError(
      'Missing ${file.path}. Regenerate it with:\n'
      '  node phantom_eye/tool/gen_places_fixture.mjs > ${file.path}\n'
      'run from the repository root.',
    );
  }
  final reference = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final expected = (reference['places'] as List).cast<Map<String, dynamic>>();

  group('curated places parity', () {
    test('the same places in the same order', () {
      expect(
        kCuratedPlaces.map((p) => p.id),
        expected.map((p) => p['id']),
        reason: 'order is display order on the home screen',
      );
    });

    test('every field matches the legacy source', () {
      for (var i = 0; i < expected.length; i++) {
        final want = expected[i];
        final got = kCuratedPlaces[i];
        final where = 'places[$i] (${want['id']})';

        expect(got.id, want['id'], reason: where);
        expect(got.name, want['name'], reason: where);
        expect(got.region, want['region'], reason: where);
        expect(got.position.lon, want['lon'], reason: '$where lon');
        expect(got.position.lat, want['lat'], reason: '$where lat');
        expect(
          got.cameraHeightMeters,
          want['cameraHeightMeters'],
          reason: '$where height',
        );
        expect(
          got.headingDegrees,
          want['headingDegrees'],
          reason: '$where heading',
        );
        expect(got.pitchDegrees, want['pitchDegrees'], reason: '$where pitch');
      }
    });

    test('no place was added or dropped on either side', () {
      expect(kCuratedPlaces, hasLength(expected.length));
    });
  });
}
