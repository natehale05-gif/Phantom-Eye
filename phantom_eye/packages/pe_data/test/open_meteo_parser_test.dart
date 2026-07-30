import 'package:pe_core/pe_core.dart';
import 'package:pe_data/pe_data.dart';
import 'package:test/test.dart';

/// Pacific Daylight Time, the zone the legacy bug was easiest to see in.
const _pdt = ForecastTimeZone(
  name: 'America/Los_Angeles',
  abbreviation: 'PDT',
  utcOffset: Duration(hours: -7),
);

/// Hourly wall-clock strings at the location, on the hour.
List<String> _hours(int startHour, int count) => [
  for (var i = 0; i < count; i++)
    '2026-07-30T${(startHour + i).toString().padLeft(2, '0')}:00',
];

Map<String, dynamic> _forecast({
  int utcOffsetSeconds = -7 * 3600,
  List<String>? hourlyTime,
  List<Object?>? uvIndex,
  List<Object?>? visibility,
  Map<String, dynamic>? daily,
  Map<String, dynamic>? current,
}) {
  final times = hourlyTime ?? _hours(11, 6);
  return {
    'utc_offset_seconds': utcOffsetSeconds,
    'timezone': 'America/Los_Angeles',
    'timezone_abbreviation': 'PDT',
    'current':
        current ??
        {
          'temperature_2m': 78.4,
          'apparent_temperature': 80.1,
          'weather_code': 1,
          'is_day': 1,
          'relative_humidity_2m': 44,
          'pressure_msl': 1014.2,
          'wind_speed_10m': 6.3,
          'wind_direction_10m': 315,
          'wind_gusts_10m': 12.1,
          'cloud_cover': 12,
          'precipitation': 0,
        },
    'hourly': {
      'time': times,
      'temperature_2m': [for (var i = 0; i < times.length; i++) 60 + i],
      'weather_code': [for (var i = 0; i < times.length; i++) i.isEven ? 0 : 3],
      'is_day': [for (var i = 0; i < times.length; i++) 1],
      'precipitation_probability': [
        for (var i = 0; i < times.length; i++) i * 2,
      ],
      'wind_speed_10m': [for (var i = 0; i < times.length; i++) 5 + i],
      'uv_index': uvIndex ?? [for (var i = 0; i < times.length; i++) i * 1.0],
      'visibility':
          visibility ?? [for (var i = 0; i < times.length; i++) 1000 * (i + 1)],
    },
    'daily':
        daily ??
        {
          'time': ['2026-07-30', '2026-07-31'],
          'weather_code': [1, 3],
          'temperature_2m_max': [84.0, 79.0],
          'temperature_2m_min': [55.0, 58.0],
          'sunrise': ['2026-07-30T05:57', '2026-07-31T05:58'],
          'sunset': ['2026-07-30T20:38', '2026-07-31T20:37'],
          'uv_index_max': [7.9, 6.4],
          'precipitation_probability_max': [0, 15],
          'wind_speed_10m_max': [11.2, 9.8],
        },
  };
}

void main() {
  group('parseForecastTimeZone', () {
    test('reads the offset and names', () {
      final zone = parseForecastTimeZone(_forecast());
      expect(zone.name, 'America/Los_Angeles');
      expect(zone.abbreviation, 'PDT');
      expect(zone.utcOffset, const Duration(hours: -7));
    });

    test('falls back to the device zone when no offset is present', () {
      final zone = parseForecastTimeZone(const {});
      expect(zone.utcOffset, DateTime.now().timeZoneOffset);
    });

    test('wallClock round-trips an instant back to location-local fields', () {
      final instant = DateTime.utc(2026, 7, 30, 20);
      final local = _pdt.wallClock(instant);
      expect(local.hour, 13);
      expect(local.day, 30);
    });
  });

  group('parseOpenMeteoTime', () {
    test('a naive string is read as wall clock at the LOCATION', () {
      // 13:00 in PDT is 20:00 UTC. Reading the string as device time — which
      // is what both `new Date(...)` and `DateTime.parse` do — would label
      // every hour of a Tokyo forecast wrong when viewed from California.
      expect(
        parseOpenMeteoTime('2026-07-30T13:00', _pdt),
        DateTime.utc(2026, 7, 30, 20),
      );
    });

    test('a date-only string resolves to local midnight', () {
      expect(
        parseOpenMeteoTime('2026-07-30', _pdt),
        DateTime.utc(2026, 7, 30, 7),
      );
    });

    test('a string that already carries a zone is not shifted twice', () {
      // Open-Meteo emits this form for `timezone=UTC`; applying the offset to
      // an already-absolute instant would move it by another 7 hours.
      expect(
        parseOpenMeteoTime('2026-07-30T20:00Z', _pdt),
        DateTime.utc(2026, 7, 30, 20),
      );
      expect(
        parseOpenMeteoTime('2026-07-30T13:00-07:00', _pdt),
        DateTime.utc(2026, 7, 30, 20),
      );
    });

    test('a positive offset is applied in the right direction', () {
      const tokyo = ForecastTimeZone(
        name: 'Asia/Tokyo',
        abbreviation: 'JST',
        utcOffset: Duration(hours: 9),
      );
      expect(
        parseOpenMeteoTime('2026-07-31T09:00', tokyo),
        DateTime.utc(2026, 7, 31, 0),
      );
    });

    test('unusable values yield null rather than throwing', () {
      expect(parseOpenMeteoTime(null, _pdt), isNull);
      expect(parseOpenMeteoTime('', _pdt), isNull);
      expect(parseOpenMeteoTime('not a time', _pdt), isNull);
      expect(parseOpenMeteoTime(42, _pdt), isNull);
    });
  });

  group('parseCurrentBrief', () {
    test('reads temp, code and day flag', () {
      final brief = parseCurrentBrief({
        'current': {'temperature_2m': 71.2, 'weather_code': 3, 'is_day': 0},
      });
      expect(brief.temp, 71.2);
      expect(brief.code, 3);
      expect(brief.isDay, isFalse);
    });

    test('missing blocks throw rather than render zeros', () {
      expect(
        () => parseCurrentBrief(const {}),
        throwsA(isA<WeatherException>()),
      );
      expect(
        () => parseCurrentBrief({'current': <String, dynamic>{}}),
        throwsA(isA<WeatherException>()),
      );
    });
  });

  group('parseForecast — current block', () {
    test('maps every field the weather page renders', () {
      final w = parseForecast(
        _forecast(),
        position: const LngLat(-123.262, 44.5646),
        name: 'Corvallis',
        now: DateTime.utc(2026, 7, 30, 20, 30),
      );
      expect(w.name, 'Corvallis');
      expect(w.position, const LngLat(-123.262, 44.5646));
      expect(w.current.temp, 78.4);
      expect(w.current.feelsLike, 80.1);
      expect(w.current.code, 1);
      expect(w.current.isDay, isTrue);
      expect(w.current.humidity, 44);
      expect(w.current.pressure, 1014.2);
      expect(w.current.windSpeed, 6.3);
      expect(w.current.windDir, 315);
      expect(w.current.windGust, 12.1);
      expect(w.current.cloud, 12);
      expect(w.current.precip, 0);
    });

    test('a missing current block throws', () {
      final body = _forecast()..remove('current');
      expect(
        () => parseForecast(
          body,
          position: const LngLat(0, 0),
          name: 'X',
          now: DateTime.utc(2026),
        ),
        throwsA(isA<WeatherException>()),
      );
    });
  });

  group('parseForecast — the hourly window', () {
    test('the strip starts at the hour containing now', () {
      // Hours are 11:00–16:00 local (18:00–23:00 UTC); now is 13:30 local.
      final w = parseForecast(
        _forecast(),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20, 30),
      );
      expect(_pdt.wallClock(w.hourly.first.time).hour, 13);
    });

    test('ON the hour it is still the CURRENT hour, not the previous one', () {
      // The legacy predicate was `t >= now - 1h`, whose first survivor at
      // 13:00 sharp is the 12:00 entry — so the UV index and visibility on
      // the card were an hour stale.
      final w = parseForecast(
        _forecast(),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(_pdt.wallClock(w.hourly.first.time).hour, 13);
      // uv_index[i] == i, and 13:00 is index 2 of the 11:00-start series.
      expect(w.current.uv, 2.0, reason: 'the 13:00 value, not 12:00\'s 1.0');
      expect(w.current.visibility, 3000);
    });

    test('uv and visibility come from that same first retained hour', () {
      final w = parseForecast(
        _forecast(),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 22, 5),
      );
      expect(_pdt.wallClock(w.hourly.first.time).hour, 15);
      expect(w.current.uv, 4.0);
      expect(w.current.visibility, 5000);
    });

    test('the window is capped at 24 hours', () {
      final w = parseForecast(
        _forecast(hourlyTime: _hours(0, 48)),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 7),
      );
      expect(w.hourly, hasLength(kForecastHours));
    });

    test('a forecast entirely in the future starts at its first entry', () {
      final w = parseForecast(
        _forecast(),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30),
      );
      expect(_pdt.wallClock(w.hourly.first.time).hour, 11);
    });

    test('missing uv and visibility arrays default to zero, not null', () {
      final w = parseForecast(
        _forecast(uvIndex: null, visibility: null)
          ..['hourly'] = {
            'time': _hours(11, 3),
            'temperature_2m': [60, 61, 62],
            'weather_code': [0, 0, 0],
            'is_day': [1, 1, 1],
            'wind_speed_10m': [5, 5, 5],
          },
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(w.current.uv, 0);
      expect(w.current.visibility, 0);
      expect(w.hourly.first.precipProb, 0);
    });

    test('an absent hourly block yields an empty strip, not a throw', () {
      final body = _forecast()..remove('hourly');
      final w = parseForecast(
        body,
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(w.hourly, isEmpty);
      expect(w.current.uv, 0);
    });

    test('hourly fields are read at the right index', () {
      final w = parseForecast(
        _forecast(),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      final first = w.hourly.first;
      expect(first.temp, 62, reason: 'index 2 of 60 + i');
      expect(first.code, 0, reason: 'even index');
      expect(first.precipProb, 4);
      expect(first.windSpeed, 7);
      expect(first.isDay, isTrue);
    });
  });

  group('parseForecast — daily and the week range', () {
    test('maps each day, resolving sunrise and sunset as location-local', () {
      final w = parseForecast(
        _forecast(),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(w.daily, hasLength(2));
      final d = w.daily.first;
      expect(d.code, 1);
      expect(d.max, 84.0);
      expect(d.min, 55.0);
      expect(d.uvMax, 7.9);
      expect(d.precipProb, 0);
      expect(d.windMax, 11.2);
      expect(_pdt.wallClock(d.sunrise!).hour, 5);
      expect(_pdt.wallClock(d.sunrise!).minute, 57);
      expect(_pdt.wallClock(d.sunset!).hour, 20);
    });

    test('the week range spans every day', () {
      final w = parseForecast(
        _forecast(),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(w.weekMin, 55.0);
      expect(w.weekMax, 84.0);
    });

    test('an EMPTY forecast yields null, not Infinity', () {
      // `Math.min(...[])` is `Infinity` in JavaScript, so the original's
      // 10-day range bars divided by an infinite span and silently collapsed
      // to slivers. Absence has to be representable.
      final w = parseForecast(
        _forecast(daily: {'time': <String>[]}),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(w.daily, isEmpty);
      expect(w.weekMin, isNull);
      expect(w.weekMax, isNull);
      expect(w.weekMin, isNot(double.infinity));
    });

    test('an absent daily block behaves the same way', () {
      final body = _forecast()..remove('daily');
      final w = parseForecast(
        body,
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(w.daily, isEmpty);
      expect(w.weekMin, isNull);
    });

    test('days with unparseable timestamps are skipped', () {
      final w = parseForecast(
        _forecast(
          daily: {
            'time': ['nope', '2026-07-31'],
            'weather_code': [1, 3],
            'temperature_2m_max': [84.0, 79.0],
            'temperature_2m_min': [55.0, 58.0],
          },
        ),
        position: const LngLat(0, 0),
        name: 'X',
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(w.daily, hasLength(1));
      // The skipped day's values must not leak into the surviving row.
      expect(w.daily.single.max, 79.0);
      expect(w.daily.single.sunrise, isNull);
    });
  });

  group('celsiusToFahrenheit', () {
    test('converts', () {
      expect(celsiusToFahrenheit(0), 32);
      expect(celsiusToFahrenheit(100), 212);
      expect(celsiusToFahrenheit(15), 59);
    });

    test('null stays null — no reading is not zero degrees', () {
      expect(celsiusToFahrenheit(null), isNull);
    });
  });

  group('parseMarine', () {
    Map<String, dynamic> marine({
      Map<String, dynamic>? current,
      Map<String, dynamic>? hourly,
      Object? error,
    }) => {
      'utc_offset_seconds': -7 * 3600,
      'timezone': 'America/Los_Angeles',
      'timezone_abbreviation': 'PDT',
      'error': ?error,
      'current':
          current ??
          {
            'wave_height': 4.2,
            'wave_period': 11.0,
            'wave_direction': 290,
            'swell_wave_height': 3.6,
            'swell_wave_period': 13.0,
            'swell_wave_direction': 295,
            'sea_surface_temperature': 13.0,
          },
      'hourly':
          hourly ??
          {
            'time': _hours(11, 4),
            'wave_height': [4.0, 4.2, 4.4, 4.1],
            'wave_period': [10.0, 11.0, 11.5, 11.0],
            'wave_direction': [288, 290, 291, 289],
            'swell_wave_height': [3.4, 3.6, 3.8, 3.5],
            'swell_wave_period': [12.0, 13.0, 13.5, 13.0],
            'swell_wave_direction': [293, 295, 296, 294],
          },
      'daily': {
        'time': ['2026-07-30', '2026-07-31'],
        'wave_height_max': [4.6, 5.1],
        'wave_period_max': [12.0, 13.0],
        'wave_direction_dominant': [291, 288],
      },
    };

    test('maps current, hourly and daily', () {
      final m = parseMarine(marine(), now: DateTime.utc(2026, 7, 30, 20, 30));
      expect(m.current.waveHeight, 4.2);
      expect(m.current.wavePeriod, 11.0);
      expect(m.current.waveDir, 290);
      expect(m.current.swellHeight, 3.6);
      expect(m.current.swellPeriod, 13.0);
      expect(m.current.swellDir, 295);
      // 13 °C water, reported in °F.
      expect(m.current.waterTemp, closeTo(55.4, 1e-9));

      // The strip starts at 13:00, which is index 2 of the 11:00-start series.
      expect(_pdt.wallClock(m.hourly.first.time).hour, 13);
      expect(m.hourly.first.waveHeight, 4.4);
      expect(m.hourly.first.swellPeriod, 13.5);

      expect(m.daily, hasLength(2));
      expect(m.daily.first.waveMax, 4.6);
      expect(m.daily.last.dirDominant, 288);
    });

    test('the surf strip starts at the current hour too', () {
      final m = parseMarine(marine(), now: DateTime.utc(2026, 7, 30, 21));
      expect(_pdt.wallClock(m.hourly.first.time).hour, 14);
    });

    test('hourly swell falls back to the wave figures when absent', () {
      // Not every marine model separates swell from total sea state.
      final m = parseMarine(
        marine(
          hourly: {
            'time': _hours(13, 1),
            'wave_height': [4.2],
            'wave_period': [11.0],
            'wave_direction': [290],
          },
        ),
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(m.hourly.single.swellHeight, 4.2);
      expect(m.hourly.single.swellPeriod, 11.0);
      expect(m.hourly.single.swellDir, 290);
    });

    test('CURRENT swell falls back too, instead of rendering NaN', () {
      // The original read `d.current.swell_wave_*` with no fallback, so at a
      // spot whose model omits them the surf card showed `NaN ft`.
      final m = parseMarine(
        marine(
          current: {
            'wave_height': 4.2,
            'wave_period': 11.0,
            'wave_direction': 290,
          },
        ),
        now: DateTime.utc(2026, 7, 30, 20),
      );
      expect(m.current.swellHeight, 4.2);
      expect(m.current.swellPeriod, 11.0);
      expect(m.current.swellDir, 290);
      expect(m.current.waterTemp, isNull);
    });

    test('an inland point with a null wave height is rejected', () {
      // Open-Meteo answers 200 for a coordinate with no marine coverage, so
      // "no data" has to be read out of the payload, not the status code.
      expect(
        () => parseMarine(
          marine(current: {'wave_height': null}),
          now: DateTime.utc(2026),
        ),
        throwsA(isA<WeatherException>()),
      );
      expect(
        () => parseMarine(
          marine(current: <String, dynamic>{}),
          now: DateTime.utc(2026),
        ),
        throwsA(isA<WeatherException>()),
      );
    });

    test('an explicit error flag is rejected', () {
      expect(
        () => parseMarine(marine(error: true), now: DateTime.utc(2026)),
        throwsA(isA<WeatherException>()),
      );
    });

    test('the surf strip is capped at 24 hours as well', () {
      final m = parseMarine(
        marine(
          hourly: {
            'time': _hours(0, 48),
            'wave_height': [for (var i = 0; i < 48; i++) 4.0],
            'wave_period': [for (var i = 0; i < 48; i++) 11.0],
            'wave_direction': [for (var i = 0; i < 48; i++) 290],
          },
        ),
        now: DateTime.utc(2026, 7, 30, 7),
      );
      expect(m.hourly, hasLength(kForecastHours));
    });

    test('SurfHour.withWind fills in the wind the marine API omits', () {
      final m = parseMarine(marine(), now: DateTime.utc(2026, 7, 30, 20));
      expect(m.hourly.first.windSpeed, 0, reason: 'marine carries no wind');
      final windy = m.hourly.first.withWind(speed: 8.5, direction: 110);
      expect(windy.windSpeed, 8.5);
      expect(windy.windDir, 110);
      expect(windy.waveHeight, m.hourly.first.waveHeight);
      expect(windy.time, m.hourly.first.time);
    });
  });
}
