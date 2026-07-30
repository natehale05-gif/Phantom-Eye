@Tags(['parity'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:pe_core/pe_core.dart';
import 'package:pe_data/pe_data.dart';
import 'package:test/test.dart';

/// Cross-checks the Dart maneuver port against the legacy TypeScript.
///
/// `test/fixtures/routing_reference.json` is produced by
/// `tool/gen_routing_fixture.mjs`, which compiles and runs the real
/// `src/routing.ts`. CI regenerates it before running this suite, so an edit
/// to either side that changes behaviour fails the build rather than quietly
/// diverging. Hand-written expectations could not do this — they accept a
/// plausible-looking transcription error just as happily as a correct port.

/// The legacy `ManeuverKind` strings are kebab-case; the Dart enum is not.
const Map<String, ManeuverKind> _kinds = {
  'depart': ManeuverKind.depart,
  'straight': ManeuverKind.straight,
  'left': ManeuverKind.left,
  'slight-left': ManeuverKind.slightLeft,
  'sharp-left': ManeuverKind.sharpLeft,
  'right': ManeuverKind.right,
  'slight-right': ManeuverKind.slightRight,
  'sharp-right': ManeuverKind.sharpRight,
  'uturn': ManeuverKind.uturn,
  'roundabout': ManeuverKind.roundabout,
  'merge': ManeuverKind.merge,
  'ramp': ManeuverKind.ramp,
  'arrive': ManeuverKind.arrive,
};

void main() {
  final file = File('test/fixtures/routing_reference.json');
  if (!file.existsSync()) {
    throw StateError(
      'Missing ${file.path}. Regenerate it with:\n'
      '  node phantom_eye/tool/gen_routing_fixture.mjs > '
      '${file.path}\n'
      'run from the repository root.',
    );
  }
  final reference = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (reference['maneuvers'] as List).cast<Map<String, dynamic>>();

  group('legacy parity', () {
    test('the fixture covers every maneuver kind', () {
      final covered = {for (final c in cases) _kinds[c['kind'] as String]};
      expect(covered, containsAll(ManeuverKind.values));
    });

    test('classifyManeuver agrees on all ${cases.length} cases', () {
      for (final c in cases) {
        expect(
          classifyManeuver(
            type: c['type'] as String?,
            modifier: c['modifier'] as String?,
          ),
          _kinds[c['kind'] as String],
          reason: 'type=${c['type']} modifier=${c['modifier']}',
        );
      }
    });

    test('describeManeuver agrees on all ${cases.length} cases', () {
      for (final c in cases) {
        final kind = _kinds[c['kind'] as String]!;
        expect(
          describeManeuver(c['name'] as String?, kind),
          c['instruction'],
          reason: 'name=${c['name']} kind=${c['kind']}',
        );
      }
    });

    test('parseOsrmResponse agrees end to end on the same payload', () {
      // Rebuild the exact response the generator fed to the legacy code, so
      // leg flattening and the distance/duration defaults are compared too,
      // not just the two pure functions.
      final half = (cases.length + 1) ~/ 2;
      Map<String, dynamic> step(Map<String, dynamic> c) => {
        'name': ?c['name'],
        'distance': 12.5,
        'maneuver': {
          'type': ?c['type'],
          'modifier': ?c['modifier'],
          'location': [-122.0, 37.0],
        },
      };

      final routes = parseOsrmResponse({
        'code': 'Ok',
        'routes': [
          {
            'geometry': {
              'coordinates': [
                [-122.0, 37.0],
                [-122.001, 37.001],
              ],
            },
            'legs': [
              {
                'steps': [for (final c in cases.take(half)) step(c)],
              },
              {
                'steps': [for (final c in cases.skip(half)) step(c)],
              },
            ],
            'distance': 1234.5,
            'duration': 678.9,
          },
          {
            'geometry': {
              'coordinates': [
                [-122.0, 37.0],
                [-122.002, 37.002],
              ],
            },
          },
        ],
      });

      expect(routes, hasLength(reference['routeCount']));
      final primary = routes.first;
      expect(primary.steps, hasLength(reference['stepCount']));
      expect(primary.distance, reference['distance']);
      expect(primary.duration, reference['duration']);

      for (var i = 0; i < cases.length; i++) {
        expect(
          primary.steps[i].instruction,
          cases[i]['instruction'],
          reason: 'step $i',
        );
        expect(primary.steps[i].kind, _kinds[cases[i]['kind'] as String]);
      }

      // A route with no legs and no totals: zero steps, zero distance.
      expect(routes[1].steps, hasLength(reference['alternateStepCount']));
      expect(routes[1].distance, reference['alternateDistance']);
      expect(routes[1].duration, reference['alternateDuration']);
    });
  });
}
