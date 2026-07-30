import 'package:pe_core/pe_core.dart';

/// Parsers for Open-Meteo's forecast and marine endpoints.
///
/// Ported from `src/weather.ts`. Every function here is pure over already
/// decoded JSON and takes `now` explicitly, so the time-window behaviour —
/// which hour counts as "current", where the 24-hour strip starts — is
/// testable without waiting for a clock.

/// How many hours the strip shows.
///
/// Ported from `if (hourly.length >= 24) break` in `src/weather.ts:164`.
const int kForecastHours = 24;

/// Thrown when a response cannot be turned into a forecast.
final class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;

  @override
  String toString() => 'WeatherException: $message';
}

/// Read the location's zone out of a response.
///
/// Falls back to the device zone when the fields are missing, which keeps the
/// legacy behaviour as the *degraded* path rather than the default one.
ForecastTimeZone parseForecastTimeZone(Map<String, dynamic> body) {
  final offset = body['utc_offset_seconds'];
  if (offset is! num) return ForecastTimeZone.local();
  return ForecastTimeZone(
    name: _str(body['timezone']) ?? 'UTC',
    abbreviation: _str(body['timezone_abbreviation']) ?? 'UTC',
    utcOffset: Duration(seconds: offset.toInt()),
  );
}

/// Resolve one Open-Meteo timestamp into a true instant.
///
/// With `timezone=auto` the strings are local-naive (`2026-07-30T13:00`), so
/// the components are read as wall clock at the location and the zone offset
/// is subtracted. A string that *does* carry `Z` or an explicit offset is
/// already absolute and is parsed as-is — Open-Meteo emits that form when
/// asked for `timezone=UTC`, and misreading it would shift every hour twice.
DateTime? parseOpenMeteoTime(Object? value, ForecastTimeZone zone) {
  if (value is! String || value.isEmpty) return null;
  if (_absoluteTime.hasMatch(value)) {
    return DateTime.tryParse(value)?.toUtc();
  }
  // Appending `Z` makes Dart read the naive components as UTC; subtracting
  // the location's offset then turns that wall clock into the real instant.
  //
  // The daily arrays are date-only (`2026-07-30`), and Dart's ISO-8601 parser
  // rejects a zone designator on a bare date — `2026-07-30Z` does not parse.
  // A midnight time part has to be supplied first, or every day of the 10-day
  // forecast is silently dropped.
  final hasTimePart = value.contains('T') || value.contains(' ');
  final asUtc = DateTime.tryParse(
    hasTimePart ? '${value}Z' : '${value}T00:00Z',
  );
  if (asUtc == null) return null;
  return asUtc.subtract(zone.utcOffset);
}

final RegExp _absoluteTime = RegExp(r'(Z|z|[+-]\d{2}:?\d{2})$');

/// Parse the trimmed `current=` response behind the at-a-glance weather chip.
///
/// Ported from `fetchCurrentBrief` in `src/weather.ts:93`.
({double temp, int code, bool isDay}) parseCurrentBrief(
  Map<String, dynamic> body,
) {
  final current = body['current'];
  if (current is! Map<String, dynamic>) {
    throw const WeatherException('response had no current block');
  }
  final temp = _num(current['temperature_2m']);
  if (temp == null) {
    throw const WeatherException('response had no current temperature');
  }
  return (
    temp: temp,
    code: _num(current['weather_code'])?.round() ?? 0,
    isDay: _num(current['is_day']) == 1,
  );
}

/// Parse the full forecast response.
///
/// [now] is the instant the strip is anchored to; pass the real clock in
/// production and a fixed value in tests.
///
/// Ported from `fetchWeather` in `src/weather.ts:109`, with two behaviour
/// changes, both noted on the fields they affect: timestamps resolve against
/// the *location's* zone rather than the device's, and `uv`/`visibility` read
/// the hour that actually contains [now].
WeatherData parseForecast(
  Map<String, dynamic> body, {
  required LngLat position,
  required String name,
  required DateTime now,
}) {
  final zone = parseForecastTimeZone(body);

  final current = body['current'];
  if (current is! Map<String, dynamic>) {
    throw const WeatherException('response had no current block');
  }

  final hourlyBlock = body['hourly'];
  final hours = <HourPoint>[];
  var uv = 0.0;
  var visibility = 0.0;

  if (hourlyBlock is Map<String, dynamic>) {
    final times = _list(hourlyBlock['time']);
    final instants = <DateTime?>[
      for (final t in times) parseOpenMeteoTime(t, zone),
    ];

    // The index of the hour containing `now`: the last entry at or before it.
    //
    // The original instead kept every entry with `t >= now - 1h` and treated
    // the first survivor as current. On the hour that is the *previous*
    // hour — 13:00 sharp keeps the 12:00 entry — so the UV index and
    // visibility shown were an hour stale, and once the device zone differed
    // from the location's they were stale by that difference too.
    var start = 0;
    for (var i = 0; i < instants.length; i++) {
      final t = instants[i];
      if (t == null) continue;
      if (!t.isAfter(now)) start = i;
    }

    final temps = _list(hourlyBlock['temperature_2m']);
    final codes = _list(hourlyBlock['weather_code']);
    final isDay = _list(hourlyBlock['is_day']);
    final precipProb = _list(hourlyBlock['precipitation_probability']);
    final wind = _list(hourlyBlock['wind_speed_10m']);
    final uvIndex = _list(hourlyBlock['uv_index']);
    final visibilities = _list(hourlyBlock['visibility']);

    for (var i = start; i < instants.length; i++) {
      final t = instants[i];
      if (t == null) continue;
      hours.add(
        HourPoint(
          time: t,
          temp: _at(temps, i) ?? 0,
          code: _at(codes, i)?.round() ?? 0,
          isDay: _at(isDay, i) == 1,
          precipProb: _at(precipProb, i) ?? 0,
          windSpeed: _at(wind, i) ?? 0,
        ),
      );
      if (hours.length == 1) {
        uv = _at(uvIndex, i) ?? 0;
        visibility = _at(visibilities, i) ?? 0;
      }
      if (hours.length >= kForecastHours) break;
    }
  }

  final days = <DayPoint>[];
  final dailyBlock = body['daily'];
  if (dailyBlock is Map<String, dynamic>) {
    final times = _list(dailyBlock['time']);
    final codes = _list(dailyBlock['weather_code']);
    final maxima = _list(dailyBlock['temperature_2m_max']);
    final minima = _list(dailyBlock['temperature_2m_min']);
    final sunrise = _list(dailyBlock['sunrise']);
    final sunset = _list(dailyBlock['sunset']);
    final uvMax = _list(dailyBlock['uv_index_max']);
    final precipMax = _list(dailyBlock['precipitation_probability_max']);
    final windMax = _list(dailyBlock['wind_speed_10m_max']);

    for (var i = 0; i < times.length; i++) {
      final t = parseOpenMeteoTime(times[i], zone);
      if (t == null) continue;
      days.add(
        DayPoint(
          time: t,
          code: _at(codes, i)?.round() ?? 0,
          min: _at(minima, i) ?? 0,
          max: _at(maxima, i) ?? 0,
          sunrise: parseOpenMeteoTime(_atRaw(sunrise, i), zone),
          sunset: parseOpenMeteoTime(_atRaw(sunset, i), zone),
          uvMax: _at(uvMax, i) ?? 0,
          precipProb: _at(precipMax, i) ?? 0,
          windMax: _at(windMax, i) ?? 0,
        ),
      );
    }
  }

  // Null rather than ±Infinity for an empty forecast. See [WeatherData].
  double? weekMin;
  double? weekMax;
  for (final d in days) {
    weekMin = weekMin == null || d.min < weekMin ? d.min : weekMin;
    weekMax = weekMax == null || d.max > weekMax ? d.max : weekMax;
  }

  return WeatherData(
    position: position,
    name: name,
    timeZone: zone,
    current: CurrentWeather(
      temp: _num(current['temperature_2m']) ?? 0,
      feelsLike: _num(current['apparent_temperature']) ?? 0,
      code: _num(current['weather_code'])?.round() ?? 0,
      isDay: _num(current['is_day']) == 1,
      humidity: _num(current['relative_humidity_2m']) ?? 0,
      pressure: _num(current['pressure_msl']) ?? 0,
      windSpeed: _num(current['wind_speed_10m']) ?? 0,
      windDir: _num(current['wind_direction_10m']) ?? 0,
      windGust: _num(current['wind_gusts_10m']) ?? 0,
      cloud: _num(current['cloud_cover']) ?? 0,
      precip: _num(current['precipitation']) ?? 0,
      uv: uv,
      visibility: visibility,
    ),
    hourly: hours,
    daily: days,
    weekMin: weekMin,
    weekMax: weekMax,
  );
}

/// Convert the marine endpoint's °C sea-surface temperature to °F.
double? celsiusToFahrenheit(double? c) => c == null ? null : c * 1.8 + 32;

/// Parse the marine response.
///
/// Ported from `fetchMarine` in `src/weather.ts:187`. Throws when the point
/// has no marine coverage — Open-Meteo answers 200 with a null `wave_height`
/// for inland coordinates, so "no data" has to be detected from the payload
/// rather than the status code.
MarineData parseMarine(Map<String, dynamic> body, {required DateTime now}) {
  if (body['error'] == true) throw const WeatherException('No marine data');
  final current = body['current'];
  if (current is! Map<String, dynamic> ||
      _num(current['wave_height']) == null) {
    throw const WeatherException('No marine data');
  }

  final zone = parseForecastTimeZone(body);

  final hours = <SurfHour>[];
  final hourlyBlock = body['hourly'];
  if (hourlyBlock is Map<String, dynamic>) {
    final times = _list(hourlyBlock['time']);
    final waveHeight = _list(hourlyBlock['wave_height']);
    final wavePeriod = _list(hourlyBlock['wave_period']);
    final waveDir = _list(hourlyBlock['wave_direction']);
    final swellHeight = _list(hourlyBlock['swell_wave_height']);
    final swellPeriod = _list(hourlyBlock['swell_wave_period']);
    final swellDir = _list(hourlyBlock['swell_wave_direction']);

    final instants = <DateTime?>[
      for (final t in times) parseOpenMeteoTime(t, zone),
    ];
    var start = 0;
    for (var i = 0; i < instants.length; i++) {
      final t = instants[i];
      if (t == null) continue;
      if (!t.isAfter(now)) start = i;
    }

    for (var i = start; i < instants.length; i++) {
      final t = instants[i];
      if (t == null) continue;
      final wave = _at(waveHeight, i) ?? 0;
      final period = _at(wavePeriod, i) ?? 0;
      hours.add(
        SurfHour(
          time: t,
          waveHeight: wave,
          wavePeriod: period,
          // Not every marine model separates swell from total sea state, so
          // the wave figures stand in when the swell fields are absent.
          swellHeight: _at(swellHeight, i) ?? wave,
          swellPeriod: _at(swellPeriod, i) ?? period,
          swellDir: _at(swellDir, i) ?? _at(waveDir, i) ?? 0,
          windSpeed: 0,
          windDir: 0,
        ),
      );
      if (hours.length >= kForecastHours) break;
    }
  }

  final days = <SurfDay>[];
  final dailyBlock = body['daily'];
  if (dailyBlock is Map<String, dynamic>) {
    final times = _list(dailyBlock['time']);
    final waveMax = _list(dailyBlock['wave_height_max']);
    final periodMax = _list(dailyBlock['wave_period_max']);
    final dirDominant = _list(dailyBlock['wave_direction_dominant']);
    for (var i = 0; i < times.length; i++) {
      final t = parseOpenMeteoTime(times[i], zone);
      if (t == null) continue;
      days.add(
        SurfDay(
          time: t,
          waveMax: _at(waveMax, i) ?? 0,
          periodMax: _at(periodMax, i) ?? 0,
          dirDominant: _at(dirDominant, i) ?? 0,
        ),
      );
    }
  }

  final wave = _num(current['wave_height']) ?? 0;
  final period = _num(current['wave_period']) ?? 0;
  final dir = _num(current['wave_direction']) ?? 0;
  return MarineData(
    timeZone: zone,
    current: MarineCurrent(
      waveHeight: wave,
      wavePeriod: period,
      waveDir: dir,
      // The original read the current swell fields with no fallback, so at a
      // spot whose model omits them the surf card rendered `NaN ft`. They
      // fall back to the wave figures here, exactly as the hourly ones do.
      swellHeight: _num(current['swell_wave_height']) ?? wave,
      swellPeriod: _num(current['swell_wave_period']) ?? period,
      swellDir: _num(current['swell_wave_direction']) ?? dir,
      waterTemp: celsiusToFahrenheit(_num(current['sea_surface_temperature'])),
    ),
    hourly: hours,
    daily: days,
  );
}

List<Object?> _list(Object? v) => v is List ? v : const [];

double? _at(List<Object?> list, int i) {
  if (i < 0 || i >= list.length) return null;
  final v = list[i];
  return v is num ? v.toDouble() : null;
}

Object? _atRaw(List<Object?> list, int i) =>
    (i < 0 || i >= list.length) ? null : list[i];

double? _num(Object? v) => v is num ? v.toDouble() : null;

String? _str(Object? v) => (v is String && v.isNotEmpty) ? v : null;
