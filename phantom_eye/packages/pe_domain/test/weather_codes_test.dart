import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

void main() {
  group('wmoCondition', () {
    test('clear and partly codes swap icon by day/night', () {
      expect(wmoCondition(0).icon, WeatherIcon.clearDay);
      expect(wmoCondition(0, isDay: false).icon, WeatherIcon.clearNight);
      expect(wmoCondition(1).icon, WeatherIcon.clearDay);
      expect(wmoCondition(1, isDay: false).icon, WeatherIcon.clearNight);
      expect(wmoCondition(2).icon, WeatherIcon.partlyDay);
      expect(wmoCondition(2, isDay: false).icon, WeatherIcon.partlyNight);
    });

    test('codes with no night variant ignore the flag', () {
      for (final code in [3, 45, 61, 71, 95]) {
        expect(
          wmoCondition(code).icon,
          wmoCondition(code, isDay: false).icon,
          reason: 'code $code',
        );
      }
    });

    test('labels match the original table', () {
      expect(wmoCondition(0).label, 'Clear');
      expect(wmoCondition(1).label, 'Mostly Clear');
      expect(wmoCondition(2).label, 'Partly Cloudy');
      expect(wmoCondition(3).label, 'Cloudy');
      expect(wmoCondition(48).label, 'Fog');
      expect(wmoCondition(53).label, 'Drizzle');
      expect(wmoCondition(57).label, 'Freezing Drizzle');
      expect(wmoCondition(63).label, 'Rain');
      expect(wmoCondition(67).label, 'Freezing Rain');
      expect(wmoCondition(75).label, 'Snow');
      expect(wmoCondition(77).label, 'Snow');
      expect(wmoCondition(81).label, 'Showers');
      expect(wmoCondition(86).label, 'Snow Showers');
      expect(wmoCondition(99).label, 'Thunderstorm');
    });

    test('freezing precipitation uses the sleet icon', () {
      expect(wmoCondition(56).icon, WeatherIcon.sleet);
      expect(wmoCondition(66).icon, WeatherIcon.sleet);
    });

    test('an unknown code degrades to Cloudy rather than throwing', () {
      // Open-Meteo has added codes over time; a forecast must still render.
      expect(wmoCondition(4).label, 'Cloudy');
      expect(wmoCondition(-1).label, 'Cloudy');
      expect(wmoCondition(999).icon, WeatherIcon.cloudy);
    });

    test('every icon in the set is reachable from some code', () {
      final reached = <WeatherIcon>{};
      for (var code = -1; code <= 100; code++) {
        reached.add(wmoCondition(code).icon);
        reached.add(wmoCondition(code, isDay: false).icon);
      }
      expect(reached, containsAll(WeatherIcon.values));
    });
  });

  group('compassPoint', () {
    test('the cardinals', () {
      expect(compassPoint(0), 'N');
      expect(compassPoint(90), 'E');
      expect(compassPoint(180), 'S');
      expect(compassPoint(270), 'W');
    });

    test('the intercardinals and the 16-point steps', () {
      expect(compassPoint(22.5), 'NNE');
      expect(compassPoint(45), 'NE');
      expect(compassPoint(112.5), 'ESE');
      expect(compassPoint(337.5), 'NNW');
    });

    test('bearings near 360 wrap to N instead of running off the table', () {
      // This is what the second `% 16` in the original is for: 349° rounds to
      // index 16, which would otherwise be out of range.
      expect(compassPoint(350), 'N');
      expect(compassPoint(359.9), 'N');
      expect(compassPoint(360), 'N');
      expect(compassPoint(720), 'N');
    });

    test('negative bearings are normalised, not turned into a bad index', () {
      // `bearingDeg` returns -180..180, so negatives reach here routinely.
      // The original's single `%` would have produced a negative index.
      expect(compassPoint(-90), 'W');
      expect(compassPoint(-45), 'NW');
      expect(compassPoint(-1), 'N');
      expect(compassPoint(-190), 'S');
    });
  });

  group('windRelation', () {
    test('wind opposing the swell is offshore — the good case', () {
      expect(windRelation(90, 270), WindRelation.offshore);
      expect(windRelation(100, 270), WindRelation.offshore);
    });

    test('wind arriving with the swell is onshore', () {
      expect(windRelation(270, 270), WindRelation.onshore);
      expect(windRelation(290, 270), WindRelation.onshore);
    });

    test('anything in between is cross-shore', () {
      expect(windRelation(180, 270), WindRelation.cross);
      expect(windRelation(0, 270), WindRelation.cross);
    });

    test('the boundaries sit at 45 and 135 degrees', () {
      expect(windRelation(270 + 45, 270), WindRelation.cross);
      expect(windRelation(270 + 44, 270), WindRelation.onshore);
      expect(windRelation(270 + 135, 270), WindRelation.cross);
      expect(windRelation(270 + 136, 270), WindRelation.offshore);
    });

    test('the comparison wraps across 0/360', () {
      expect(windRelation(350, 10), WindRelation.onshore);
      expect(windRelation(10, 350), WindRelation.onshore);
      expect(windRelation(190, 10), WindRelation.offshore);
    });
  });

  group('surfRating', () {
    test('big long-period swell with offshore wind rates Epic', () {
      final r = surfRating(
        swellFt: 8,
        periodS: 16,
        windMph: 4,
        relation: WindRelation.offshore,
      );
      expect(r.label, 'Epic');
      expect(r.score, greaterThanOrEqualTo(7.5));
    });

    test('flat onshore slop rates Poor', () {
      final r = surfRating(
        swellFt: 0.5,
        periodS: 5,
        windMph: 25,
        relation: WindRelation.onshore,
      );
      expect(r.label, 'Poor');
      expect(r.score, 0, reason: 'the score is clamped at zero');
    });

    test('the four bands are all reachable', () {
      final labels = <String>{};
      for (var swell = 0.0; swell <= 12; swell += 0.5) {
        for (final period in [4.0, 8.0, 12.0, 18.0]) {
          for (final wind in [0.0, 10.0, 25.0]) {
            for (final rel in WindRelation.values) {
              labels.add(
                surfRating(
                  swellFt: swell,
                  periodS: period,
                  windMph: wind,
                  relation: rel,
                ).label,
              );
            }
          }
        }
      }
      expect(labels, {'Epic', 'Good', 'Fair', 'Poor'});
    });

    test('size and period each contribute at most 3', () {
      final huge = surfRating(
        swellFt: 100,
        periodS: 100,
        windMph: 0,
        relation: WindRelation.onshore,
      );
      expect(huge.score, 6, reason: '3 for size + 3 for period, no wind bonus');
    });

    test('period only starts scoring above 6 seconds', () {
      final short = surfRating(
        swellFt: 0,
        periodS: 6,
        windMph: 0,
        relation: WindRelation.onshore,
      );
      expect(short.score, 0);
    });

    test('wind chop subtracts at most 2', () {
      final windy = surfRating(
        swellFt: 100,
        periodS: 100,
        windMph: 100,
        relation: WindRelation.offshore,
      );
      expect(windy.score, 6, reason: '3 + 3 + 2 offshore - 2 chop');
    });

    test('the score never leaves 0..10', () {
      for (final swell in [-5.0, 0.0, 50.0]) {
        for (final wind in [0.0, 200.0]) {
          for (final rel in WindRelation.values) {
            final r = surfRating(
              swellFt: swell,
              periodS: 30,
              windMph: wind,
              relation: rel,
            );
            expect(r.score, inInclusiveRange(0, 10));
          }
        }
      }
    });

    test('every band carries its own colour', () {
      final colours = <String>{};
      for (final args in [
        (8.0, 16.0, 4.0, WindRelation.offshore), // Epic
        (6.0, 12.0, 6.0, WindRelation.cross), // Good, 5.5 exactly
        (4.0, 12.0, 6.0, WindRelation.cross), // Fair
        (0.5, 5.0, 25.0, WindRelation.onshore), // Poor
      ]) {
        colours.add(
          surfRating(
            swellFt: args.$1,
            periodS: args.$2,
            windMph: args.$3,
            relation: args.$4,
          ).colorHex,
        );
      }
      expect(colours, hasLength(4));
      expect(colours, everyElement(startsWith('#')));
    });
  });
}
