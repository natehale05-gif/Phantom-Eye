import 'dart:convert';

import 'package:pe_core/pe_core.dart';
import 'package:pe_data/pe_data.dart';
import 'package:test/test.dart';

Map<String, dynamic> _route({
  List<List<double>>? coords,
  List<Map<String, dynamic>>? steps,
  double? distance,
  double? duration,
}) => {
  'geometry': {
    'coordinates':
        coords ??
        [
          [-122.0, 37.0],
          [-122.001, 37.001],
          [-122.002, 37.002],
        ],
  },
  'legs': [
    {'steps': steps ?? const []},
  ],
  'distance': ?distance,
  'duration': ?duration,
};

Map<String, dynamic> _step({
  String? type,
  String? modifier,
  String? name,
  double? distance,
  List<double> location = const [-122.0, 37.0],
}) => {
  'name': ?name,
  'distance': ?distance,
  'maneuver': {'type': ?type, 'modifier': ?modifier, 'location': location},
};

void main() {
  group('classifyManeuver', () {
    test('type wins over modifier', () {
      // A roundabout carrying a left modifier is still a roundabout. Getting
      // this backwards would render every roundabout as a plain left turn.
      expect(
        classifyManeuver(type: 'roundabout', modifier: 'left'),
        ManeuverKind.roundabout,
      );
      expect(
        classifyManeuver(type: 'depart', modifier: 'sharp right'),
        ManeuverKind.depart,
      );
      expect(
        classifyManeuver(type: 'arrive', modifier: 'uturn'),
        ManeuverKind.arrive,
      );
    });

    test('rotary is treated as a roundabout', () {
      expect(classifyManeuver(type: 'rotary'), ManeuverKind.roundabout);
    });

    test('both ramp spellings, with the space', () {
      expect(classifyManeuver(type: 'on ramp'), ManeuverKind.ramp);
      expect(classifyManeuver(type: 'off ramp'), ManeuverKind.ramp);
      // Underscored variants are NOT what OSRM sends and must not match.
      expect(classifyManeuver(type: 'on_ramp'), ManeuverKind.straight);
    });

    test('uturn matches by substring, so qualified forms still land', () {
      expect(classifyManeuver(modifier: 'uturn'), ManeuverKind.uturn);
      expect(classifyManeuver(modifier: 'sharp uturn'), ManeuverKind.uturn);
      expect(classifyManeuver(modifier: 'slight uturn'), ManeuverKind.uturn);
    });

    test('exact modifiers for the six turn kinds', () {
      expect(classifyManeuver(modifier: 'left'), ManeuverKind.left);
      expect(classifyManeuver(modifier: 'right'), ManeuverKind.right);
      expect(
        classifyManeuver(modifier: 'slight left'),
        ManeuverKind.slightLeft,
      );
      expect(
        classifyManeuver(modifier: 'slight right'),
        ManeuverKind.slightRight,
      );
      expect(classifyManeuver(modifier: 'sharp left'), ManeuverKind.sharpLeft);
      expect(
        classifyManeuver(modifier: 'sharp right'),
        ManeuverKind.sharpRight,
      );
    });

    test('merge', () {
      expect(classifyManeuver(type: 'merge'), ManeuverKind.merge);
    });

    test('unmatched types fall through to straight via their modifier', () {
      // turn/continue/new name/fork/end of road carry no distinguishing type.
      expect(
        classifyManeuver(type: 'turn', modifier: 'left'),
        ManeuverKind.left,
      );
      expect(classifyManeuver(type: 'continue'), ManeuverKind.straight);
      expect(classifyManeuver(type: 'new name'), ManeuverKind.straight);
      expect(
        classifyManeuver(type: 'fork', modifier: 'slight left'),
        ManeuverKind.slightLeft,
      );
      expect(classifyManeuver(type: 'exit roundabout'), ManeuverKind.straight);
    });

    test('missing type and modifier default to straight', () {
      expect(classifyManeuver(), ManeuverKind.straight);
      expect(classifyManeuver(type: '', modifier: ''), ManeuverKind.straight);
    });

    test('every one of the 13 kinds is reachable', () {
      final reached = {
        classifyManeuver(type: 'depart'),
        classifyManeuver(type: 'arrive'),
        classifyManeuver(type: 'roundabout'),
        classifyManeuver(type: 'merge'),
        classifyManeuver(type: 'on ramp'),
        classifyManeuver(modifier: 'uturn'),
        classifyManeuver(modifier: 'left'),
        classifyManeuver(modifier: 'right'),
        classifyManeuver(modifier: 'slight left'),
        classifyManeuver(modifier: 'slight right'),
        classifyManeuver(modifier: 'sharp left'),
        classifyManeuver(modifier: 'sharp right'),
        classifyManeuver(),
      };
      expect(reached.length, ManeuverKind.values.length);
      expect(reached, containsAll(ManeuverKind.values));
    });
  });

  group('describeManeuver', () {
    test('u-turn says "on", not "onto"', () {
      // You make a U-turn ON a street. Every other road-bearing case uses
      // "onto".
      expect(
        describeManeuver('Main St', ManeuverKind.uturn),
        'Make a U-turn on Main St',
      );
      expect(
        describeManeuver('Main St', ManeuverKind.left),
        'Turn left onto Main St',
      );
    });

    test('arrival never names a road', () {
      expect(
        describeManeuver('Main St', ManeuverKind.arrive),
        'Arrive at your destination',
      );
    });

    test('depart and straight have distinct no-road wordings', () {
      expect(describeManeuver(null, ManeuverKind.depart), 'Start');
      expect(
        describeManeuver('Main St', ManeuverKind.depart),
        'Head out on Main St',
      );
      expect(
        describeManeuver(null, ManeuverKind.straight),
        'Continue straight',
      );
      expect(
        describeManeuver('Main St', ManeuverKind.straight),
        'Continue on Main St',
      );
    });

    test('an empty or whitespace road name is treated as absent', () {
      expect(describeManeuver('', ManeuverKind.left), 'Turn left');
      expect(describeManeuver('   ', ManeuverKind.left), 'Turn left');
      expect(describeManeuver(null, ManeuverKind.left), 'Turn left');
    });

    test('road names are trimmed', () {
      expect(
        describeManeuver('  Main St  ', ManeuverKind.right),
        'Turn right onto Main St',
      );
    });

    test(
      'every kind produces a non-empty instruction, with and without a road',
      () {
        for (final kind in ManeuverKind.values) {
          expect(
            describeManeuver('Main St', kind),
            isNotEmpty,
            reason: '$kind',
          );
          expect(
            describeManeuver(null, kind),
            isNotEmpty,
            reason: '$kind null',
          );
        }
      },
    );
  });

  group('parseOsrmRoute', () {
    test('reads geometry, distance and duration', () {
      final r = parseOsrmRoute(_route(distance: 1234.5, duration: 678.9));
      expect(r.coordinates.length, 3);
      expect(r.coordinates.first, const LngLat(-122.0, 37.0));
      expect(r.distance, 1234.5);
      expect(r.duration, 678.9);
    });

    test('missing distance and duration default to zero', () {
      final r = parseOsrmRoute(_route());
      expect(r.distance, 0);
      expect(r.duration, 0);
    });

    test('flattens steps across all legs', () {
      final route = _route();
      route['legs'] = [
        {
          'steps': [_step(type: 'depart', name: 'A St')],
        },
        {
          'steps': [
            _step(modifier: 'left', name: 'B St'),
            _step(type: 'arrive'),
          ],
        },
      ];
      final r = parseOsrmRoute(route);
      expect(r.steps.length, 3, reason: 'leg boundaries are not preserved');
      expect(r.steps[0].kind, ManeuverKind.depart);
      expect(r.steps[1].instruction, 'Turn left onto B St');
      expect(r.steps[2].kind, ManeuverKind.arrive);
    });

    test('step location and distance are carried through', () {
      final route = _route(
        steps: [
          _step(modifier: 'right', distance: 42.5, location: [-121.5, 37.5]),
        ],
      );
      final r = parseOsrmRoute(route);
      expect(r.steps.single.distance, 42.5);
      expect(r.steps.single.location, const LngLat(-121.5, 37.5));
    });

    test('a step with no maneuver location is skipped, not fatal', () {
      final route = _route();
      route['legs'] = [
        {
          'steps': [
            {'maneuver': <String, dynamic>{}}, // no location
            _step(modifier: 'left', name: 'Good St'),
          ],
        },
      ];
      final r = parseOsrmRoute(route);
      expect(r.steps.length, 1);
      expect(r.steps.single.instruction, 'Turn left onto Good St');
    });

    test('absent legs yields a route with geometry but no steps', () {
      final route = _route();
      route.remove('legs');
      final r = parseOsrmRoute(route);
      expect(r.steps, isEmpty);
      expect(r.coordinates, isNotEmpty);
    });

    test('malformed geometry throws rather than silently drawing nothing', () {
      expect(() => parseOsrmRoute({}), throwsA(isA<RoutingException>()));
      expect(
        () => parseOsrmRoute({'geometry': <String, dynamic>{}}),
        throwsA(isA<RoutingException>()),
      );
      expect(
        () => parseOsrmRoute({
          'geometry': {'coordinates': <dynamic>[]},
        }),
        throwsA(isA<RoutingException>()),
      );
      // A single point is not a drawable route.
      expect(
        () => parseOsrmRoute(
          _route(
            coords: [
              [-122.0, 37.0],
            ],
          ),
        ),
        throwsA(isA<RoutingException>()),
      );
    });
  });

  group('parseOsrmResponse', () {
    test('the first route is primary and the rest are alternates', () {
      final body = {
        'code': 'Ok',
        'routes': [
          _route(distance: 100),
          _route(distance: 200),
          _route(distance: 300),
        ],
      };
      final routes = parseOsrmResponse(body);
      expect(routes.length, 3);
      expect(routes.first.distance, 100);
      expect(routes.last.distance, 300);
    });

    test('a non-Ok code or empty routes throws', () {
      expect(
        () => parseOsrmResponse({'code': 'NoRoute', 'routes': <dynamic>[]}),
        throwsA(isA<RoutingException>()),
      );
      expect(
        () => parseOsrmResponse({'code': 'Ok', 'routes': <dynamic>[]}),
        throwsA(isA<RoutingException>()),
      );
      expect(() => parseOsrmResponse({}), throwsA(isA<RoutingException>()));
    });

    test('parses a realistic captured response shape', () {
      // Shape as returned by router.project-osrm.org with
      // overview=full&geometries=geojson&steps=true.
      const raw = '''
      {
        "code": "Ok",
        "routes": [{
          "distance": 2543.1,
          "duration": 412.7,
          "geometry": {
            "coordinates": [
              [-122.4194, 37.7749], [-122.4180, 37.7760], [-122.4150, 37.7790]
            ]
          },
          "legs": [{
            "steps": [
              {"name": "Market St", "distance": 120.4,
               "maneuver": {"type": "depart", "modifier": "left",
                            "location": [-122.4194, 37.7749]}},
              {"name": "Van Ness Ave", "distance": 890.2,
               "maneuver": {"type": "turn", "modifier": "right",
                            "location": [-122.4180, 37.7760]}},
              {"name": "", "distance": 0,
               "maneuver": {"type": "arrive",
                            "location": [-122.4150, 37.7790]}}
            ]
          }]
        }]
      }
      ''';
      final routes = parseOsrmResponse(jsonDecode(raw) as Map<String, dynamic>);
      expect(routes, hasLength(1));
      final r = routes.single;
      expect(r.distance, closeTo(2543.1, 1e-9));
      expect(r.coordinates, hasLength(3));
      expect(r.steps.map((s) => s.instruction), [
        'Head out on Market St',
        'Turn right onto Van Ness Ave',
        'Arrive at your destination',
      ]);
      expect(r.steps.map((s) => s.kind), [
        ManeuverKind.depart,
        ManeuverKind.right,
        ManeuverKind.arrive,
      ]);
    });
  });

  group('durationForMode', () {
    const route = RouteModel(
      coordinates: [LngLat(0, 0), LngLat(0, 1)],
      steps: [],
      distance: 1400,
      duration: 300,
    );

    test('driving uses the provider duration', () {
      expect(durationForMode(route, TravelMode.driving), 300);
    });

    test('walking and cycling are estimated from distance', () {
      // The OSRM demo only serves the driving network, so walk/cycle reuse the
      // geometry and estimate time from distance.
      expect(durationForMode(route, TravelMode.walking), 1400 / 1.4);
      expect(durationForMode(route, TravelMode.cycling), 1400 / 4.2);
    });
  });
}
