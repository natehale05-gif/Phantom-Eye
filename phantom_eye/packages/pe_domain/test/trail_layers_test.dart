import 'package:pe_core/pe_core.dart';
import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

const _bounds = LatLngBounds(
  south: 44.54,
  west: -123.28,
  north: 44.59,
  east: -123.24,
);

Map<String, dynamic> _way(
  List<List<double>> lonLats, {
  Map<String, String> tags = const {},
}) => {
  'type': 'way',
  'tags': tags,
  'geometry': [
    for (final p in lonLats) {'lon': p[0], 'lat': p[1]},
  ],
};

Map<String, dynamic> _relation(
  List<List<List<double>>> memberGeometries, {
  Map<String, String> tags = const {},
}) => {
  'type': 'relation',
  'tags': tags,
  'members': [
    for (final geom in memberGeometries)
      {
        'type': 'way',
        'role': '',
        'geometry': [
          for (final p in geom) {'lon': p[0], 'lat': p[1]},
        ],
      },
  ],
};

List<List<double>> _line(int points) => [
  for (var i = 0; i < points; i++) [-123.26 + i * 0.0001, 44.56 + i * 0.0001],
];

void main() {
  group('buildTrailQuery', () {
    test('every clause for the layer is present with the bbox', () {
      for (final layer in TrailLayerId.values) {
        final q = buildTrailQuery(layer, _bounds);
        for (final clause in kTrailClauses[layer]!) {
          expect(
            q,
            contains('$clause(44.54,-123.28,44.59,-123.24);'),
            reason: '${layer.id}: $clause',
          );
        }
      }
    });

    test('EVERY union member ends in a semicolon, including the last', () {
      // Joining the clauses with ';' omits the final separator and Overpass
      // rejects the whole query with a 400 — a failure that reads like a dead
      // mirror rather than a malformed request.
      for (final layer in TrailLayerId.values) {
        final q = buildTrailQuery(layer, _bounds);
        final union = q.substring(q.indexOf('('), q.lastIndexOf(');') + 1);
        expect(union, endsWith(';)'), reason: layer.id);
        expect(
          union,
          isNot(contains(';;')),
          reason: '${layer.id}: no doubled separators either',
        );
      }
    });

    test('uses out geom, not out center — whole lines are needed', () {
      final q = buildTrailQuery(TrailLayerId.hiking, _bounds);
      expect(q, contains('out geom 400;'));
      expect(q, isNot(contains('out center')));
      expect(q, startsWith('[out:json][timeout:25];'));
    });

    test('only the bike layer queries relations', () {
      // Signed cycle and MTB routes are mapped as relations; nothing in the
      // hiking or offroad sets is, so querying them there is wasted recursion.
      expect(
        buildTrailQuery(TrailLayerId.bike, _bounds),
        contains('relation['),
      );
      expect(
        buildTrailQuery(TrailLayerId.hiking, _bounds),
        isNot(contains('relation[')),
      );
      expect(
        buildTrailQuery(TrailLayerId.offroad, _bounds),
        isNot(contains('relation[')),
      );
    });

    test('sidewalks are excluded from the hiking layer', () {
      // Without this every city block becomes a "trail".
      expect(
        buildTrailQuery(TrailLayerId.hiking, _bounds),
        contains('["footway"!="sidewalk"]'),
      );
    });
  });

  group('gradeTrail — hiking', () {
    test('the SAC scale maps to the four grades', () {
      const cases = {
        'hiking': TrailDifficulty.easy,
        'mountain_hiking': TrailDifficulty.intermediate,
        'demanding_mountain_hiking': TrailDifficulty.advanced,
        'alpine_hiking': TrailDifficulty.expert,
        'demanding_alpine_hiking': TrailDifficulty.expert,
        'difficult_alpine_hiking': TrailDifficulty.expert,
      };
      cases.forEach((scale, expected) {
        expect(
          gradeTrail(TrailLayerId.hiking, {'sac_scale': scale}),
          expected,
          reason: scale,
        );
      });
    });

    test('the SAC scale wins over the fallback signals', () {
      expect(
        gradeTrail(TrailLayerId.hiking, {
          'sac_scale': 'hiking',
          'highway': 'steps',
          'trail_visibility': 'horrible',
        }),
        TrailDifficulty.easy,
      );
    });

    test('steps read as intermediate without a scale', () {
      expect(
        gradeTrail(TrailLayerId.hiking, {'highway': 'steps'}),
        TrailDifficulty.intermediate,
      );
    });

    test('poor visibility reads as advanced', () {
      for (final v in ['bad', 'horrible', 'no']) {
        expect(
          gradeTrail(TrailLayerId.hiking, {'trail_visibility': v}),
          TrailDifficulty.advanced,
          reason: v,
        );
      }
      expect(
        gradeTrail(TrailLayerId.hiking, {'trail_visibility': 'excellent'}),
        TrailDifficulty.easy,
      );
    });

    test('an untagged path is easy, not unrated', () {
      expect(gradeTrail(TrailLayerId.hiking, const {}), TrailDifficulty.easy);
    });
  });

  group('gradeTrail — bike', () {
    test('the IMBA scale maps to the four grades', () {
      const cases = {
        '0': TrailDifficulty.easy,
        '1': TrailDifficulty.easy,
        '2': TrailDifficulty.intermediate,
        '3': TrailDifficulty.advanced,
        '4': TrailDifficulty.expert,
        '5': TrailDifficulty.expert,
      };
      cases.forEach((scale, expected) {
        expect(
          gradeTrail(TrailLayerId.bike, {'mtb:scale:imba': scale}),
          expected,
          reason: 'imba $scale',
        );
      });
    });

    test('IMBA wins over the plain MTB scale', () {
      expect(
        gradeTrail(TrailLayerId.bike, {
          'mtb:scale:imba': '0',
          'mtb:scale': '6',
        }),
        TrailDifficulty.easy,
      );
    });

    test('the MTB scale bands differ from IMBA', () {
      const cases = {
        '0': TrailDifficulty.easy,
        '1': TrailDifficulty.easy,
        '2': TrailDifficulty.intermediate,
        '3': TrailDifficulty.intermediate,
        '4': TrailDifficulty.advanced,
        '5': TrailDifficulty.expert,
        '6': TrailDifficulty.expert,
      };
      cases.forEach((scale, expected) {
        expect(
          gradeTrail(TrailLayerId.bike, {'mtb:scale': scale}),
          expected,
          reason: 'mtb $scale',
        );
      });
    });

    test('a plain cycleway with no scale is easy', () {
      expect(gradeTrail(TrailLayerId.bike, const {}), TrailDifficulty.easy);
    });
  });

  group('gradeTrail — offroad', () {
    test('tracktype maps to the four grades', () {
      const cases = {
        'grade1': TrailDifficulty.easy,
        'grade2': TrailDifficulty.intermediate,
        'grade3': TrailDifficulty.advanced,
        'grade4': TrailDifficulty.expert,
        'grade5': TrailDifficulty.expert,
      };
      cases.forEach((grade, expected) {
        expect(
          gradeTrail(TrailLayerId.offroad, {'tracktype': grade}),
          expected,
          reason: grade,
        );
      });
    });

    test('tracktype wins over smoothness', () {
      expect(
        gradeTrail(TrailLayerId.offroad, {
          'tracktype': 'grade1',
          'smoothness': 'impassable',
        }),
        TrailDifficulty.easy,
      );
    });

    test('smoothness is the fallback', () {
      const cases = {
        'excellent': TrailDifficulty.easy,
        'good': TrailDifficulty.easy,
        'intermediate': TrailDifficulty.intermediate,
        'bad': TrailDifficulty.advanced,
        'very_bad': TrailDifficulty.expert,
        'horrible': TrailDifficulty.expert,
        'very_horrible': TrailDifficulty.expert,
        'impassable': TrailDifficulty.expert,
      };
      cases.forEach((value, expected) {
        expect(
          gradeTrail(TrailLayerId.offroad, {'smoothness': value}),
          expected,
          reason: value,
        );
      });
    });

    test('4wd_only is the last resort before easy', () {
      expect(
        gradeTrail(TrailLayerId.offroad, {'4wd_only': 'yes'}),
        TrailDifficulty.advanced,
      );
      expect(
        gradeTrail(TrailLayerId.offroad, {'4wd_only': 'no'}),
        TrailDifficulty.easy,
      );
      expect(gradeTrail(TrailLayerId.offroad, const {}), TrailDifficulty.easy);
    });
  });

  group('leadingInt', () {
    test('reads the messy real-world MTB scale values', () {
      // `mtb:scale=3+` is common; a strict parse would drop the grading for a
      // large share of actual trails.
      expect(leadingInt('3'), 3);
      expect(leadingInt('3+'), 3);
      expect(leadingInt('S2'), 2);
      expect(leadingInt('0'), 0);
    });

    test('null for nothing numeric', () {
      expect(leadingInt(null), isNull);
      expect(leadingInt(''), isNull);
      expect(leadingInt('unknown'), isNull);
    });
  });

  group('parseTrailWays', () {
    test('maps a way and grades it from its own tags', () {
      final ways = parseTrailWays([
        _way(_line(3), tags: const {'sac_scale': 'alpine_hiking'}),
      ], TrailLayerId.hiking);
      expect(ways, hasLength(1));
      expect(ways.single.points, hasLength(3));
      expect(ways.single.difficulty, TrailDifficulty.expert);
    });

    test('relation members inherit the RELATION tags, not their own', () {
      // A signed route must share one colour along its whole length instead
      // of flickering between grades member by member.
      final ways = parseTrailWays([
        _relation(
          [_line(3), _line(4)],
          tags: const {'route': 'mtb', 'mtb:scale': '5'},
        ),
      ], TrailLayerId.bike);
      expect(ways, hasLength(2));
      expect(
        ways.map((w) => w.difficulty),
        everyElement(TrailDifficulty.expert),
      );
    });

    test('geometries under two points are dropped', () {
      final ways = parseTrailWays([
        _way(_line(1)),
        _way(const []),
        _way(_line(2)),
      ], TrailLayerId.hiking);
      expect(ways, hasLength(1));
    });

    test('elements with no geometry at all are skipped', () {
      final ways = parseTrailWays([
        {'type': 'way', 'tags': <String, String>{}},
        {'type': 'node', 'lat': 44.5, 'lon': -123.2},
        {'type': 'relation'},
        _way(_line(2)),
      ], TrailLayerId.hiking);
      expect(ways, hasLength(1));
    });

    test('non-numeric geometry points are dropped', () {
      final ways = parseTrailWays([
        {
          'type': 'way',
          'geometry': [
            {'lon': 'x', 'lat': 'y'},
            {'lon': -123.2, 'lat': 44.5},
          ],
        },
      ], TrailLayerId.hiking);
      expect(ways, isEmpty, reason: 'only one usable point remained');
    });

    test('non-string tag values do not crash the grader', () {
      final ways = parseTrailWays([
        {
          'type': 'way',
          'tags': {'sac_scale': 'hiking', 'width': 2, 'lit': null},
          'geometry': [
            {'lon': -123.2, 'lat': 44.5},
            {'lon': -123.201, 'lat': 44.501},
          ],
        },
      ], TrailLayerId.hiking);
      expect(ways.single.difficulty, TrailDifficulty.easy);
    });

    test('the way cap is honoured', () {
      final ways = parseTrailWays([
        for (var i = 0; i < 500; i++) _way(_line(2)),
      ], TrailLayerId.hiking);
      expect(ways, hasLength(kTrailMaxWays));
    });

    test('the cap also stops mid-relation', () {
      final ways = parseTrailWays(
        [
          _relation([for (var i = 0; i < 500; i++) _line(2)]),
        ],
        TrailLayerId.bike,
        maxWays: 10,
      );
      expect(ways, hasLength(10));
    });

    test('an empty response yields no ways', () {
      expect(parseTrailWays(const [], TrailLayerId.bike), isEmpty);
    });
  });

  group('downsampleTrailWay', () {
    test('a short way is returned untouched', () {
      final points = _line(10).map((p) => LngLat(p[0], p[1])).toList();
      expect(downsampleTrailWay(points), same(points));
    });

    test('a long way is thinned to the cap', () {
      final points = _line(500).map((p) => LngLat(p[0], p[1])).toList();
      final out = downsampleTrailWay(points);
      expect(out.length, lessThanOrEqualTo(kTrailMaxPointsPerWay + 1));
      expect(out.first, points.first);
    });

    test('THE FINAL VERTEX IS ALWAYS KEPT', () {
      // Striding rarely lands on the last index, and dropping it leaves the
      // drawn line stopping short of where the trail actually ends.
      for (final n in [49, 50, 97, 100, 193, 500, 1001]) {
        final points = _line(n).map((p) => LngLat(p[0], p[1])).toList();
        final out = downsampleTrailWay(points);
        expect(out.last, points.last, reason: '$n points');
      }
    });

    test('the last vertex is not duplicated when the stride lands on it', () {
      final points = _line(96).map((p) => LngLat(p[0], p[1])).toList();
      final out = downsampleTrailWay(points);
      expect(out.length, out.toSet().length, reason: 'no duplicate vertices');
    });

    test('the shape is preserved by striding, not truncating', () {
      final points = _line(200).map((p) => LngLat(p[0], p[1])).toList();
      final out = downsampleTrailWay(points);
      // A truncating implementation would keep only the first 48 points, so
      // the output would span a fraction of the original.
      final span = (out.last.lon - out.first.lon).abs();
      final fullSpan = (points.last.lon - points.first.lon).abs();
      expect(span, closeTo(fullSpan, 1e-9));
    });
  });

  group('trailViewArea', () {
    test('null above the altitude cutoff', () {
      expect(trailViewArea(const LngLat(-123.26, 44.56), 22001), isNull);
      expect(trailViewArea(const LngLat(-123.26, 44.56), 50000), isNull);
      expect(
        trailViewArea(const LngLat(-123.26, 44.56), kTrailMaxAltitudeMeters),
        isNotNull,
      );
    });

    test('a very low camera still gets the minimum span', () {
      final low = trailViewArea(const LngLat(0, 0), 10)!;
      expect(low.latSpan / 2, closeTo(kTrailMinHalfSpanDegrees, 1e-12));
    });

    test('the span scales with altitude between the clamps', () {
      final a = trailViewArea(const LngLat(0, 0), 5000)!;
      final b = trailViewArea(const LngLat(0, 0), 10000)!;
      expect(b.latSpan, closeTo(a.latSpan * 2, 1e-9));
      expect(a.latSpan / 2, closeTo(5000 / 111000 * 0.9, 1e-12));
    });

    test(
      'the UPPER clamp is unreachable — the altitude cutoff binds first',
      () {
        // At the 22 km cutoff the half-span is only 0.178°; reaching the 0.25°
        // clamp would need a camera ~30.8 km up, which is already refused. The
        // clamp is a backstop, not live behaviour — true of the original too.
        final atCutoff = trailViewArea(
          const LngLat(0, 0),
          kTrailMaxAltitudeMeters,
        )!;
        expect(atCutoff.latSpan / 2, closeTo(0.1783783783783784, 1e-12));
        expect(atCutoff.latSpan / 2, lessThan(kTrailMaxHalfSpanDegrees));
      },
    );

    test('the box is centred on the camera position', () {
      final area = trailViewArea(const LngLat(-123.26, 44.56), 5000)!;
      expect(area.center.lon, closeTo(-123.26, 1e-9));
      expect(area.center.lat, closeTo(44.56, 1e-9));
    });

    test('longitude widens with latitude, by design', () {
      // Dividing by cos(lat) keeps the queried box roughly SQUARE IN GROUND
      // DISTANCE rather than in degrees, so the same number of trails comes
      // back in Alaska as in Oregon. This reads like a missing clamp and is
      // not one — do not "fix" it.
      final equator = trailViewArea(const LngLat(0, 0), 10000)!;
      final north = trailViewArea(const LngLat(0, 60), 10000)!;
      expect(equator.latSpan, closeTo(north.latSpan, 1e-12));
      // cos(60°) = 0.5, so twice as wide.
      expect(north.lonSpan, closeTo(equator.lonSpan * 2, 1e-9));
    });

    test('the cosine is floored so the poles do not explode', () {
      final polar = trailViewArea(const LngLat(0, 89.9), 10000)!;
      expect(polar.lonSpan.isFinite, isTrue);
      final equator = trailViewArea(const LngLat(0, 0), 10000)!;
      expect(polar.lonSpan, closeTo(equator.lonSpan / 0.2, 1e-9));
    });

    test('non-finite inputs yield null rather than a NaN bbox', () {
      expect(trailViewArea(const LngLat(double.nan, 44.5), 1000), isNull);
      expect(trailViewArea(const LngLat(0, 0), double.nan), isNull);
      expect(trailViewArea(const LngLat(0, 0), double.infinity), isNull);
    });
  });

  group('trailCacheKey', () {
    test(
      'rounds to two decimal places so panning a block reuses the result',
      () {
        final a = trailCacheKey(
          const LatLngBounds(
            south: 44.561,
            west: -123.262,
            north: 44.611,
            east: -123.212,
          ),
        );
        final b = trailCacheKey(
          const LatLngBounds(
            south: 44.5614,
            west: -123.2622,
            north: 44.6108,
            east: -123.2118,
          ),
        );
        expect(a, b);
      },
    );

    test('a real move produces a different key', () {
      final a = trailCacheKey(_bounds);
      final b = trailCacheKey(
        const LatLngBounds(
          south: 44.60,
          west: -123.28,
          north: 44.65,
          east: -123.24,
        ),
      );
      expect(a, isNot(b));
    });

    test('pairs with the LRU cache from pe_core', () {
      final cache = LruCache<String, List<TrailWay>>(kTrailCacheTiles);
      for (var i = 0; i < kTrailCacheTiles + 10; i++) {
        cache.put('key$i', const []);
      }
      expect(cache.length, kTrailCacheTiles);
    });
  });

  group('TrailLayerId and TrailDifficulty', () {
    test('ids round-trip', () {
      for (final layer in TrailLayerId.values) {
        expect(TrailLayerId.parse(layer.id), layer);
      }
      expect(TrailLayerId.parse('nope'), isNull);
    });

    test('every difficulty has a distinct colour', () {
      final colours = {for (final d in TrailDifficulty.values) d.colorHex};
      expect(colours, hasLength(TrailDifficulty.values.length));
      expect(colours, everyElement(startsWith('#')));
    });

    test('the ski-run convention is preserved', () {
      expect(TrailDifficulty.easy.colorHex, '#34C759');
      expect(TrailDifficulty.intermediate.colorHex, '#0A84FF');
      expect(TrailDifficulty.advanced.colorHex, '#111111');
      expect(TrailDifficulty.expert.colorHex, '#FF3B30');
    });
  });
}
