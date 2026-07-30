import '../geo/lng_lat.dart';

/// The forecast location's own time zone.
///
/// Open-Meteo is asked for `timezone=auto`, so every timestamp it returns is a
/// **local-naive wall clock** at the forecast location — `2026-07-30T13:00`
/// with no zone designator. Both `new Date(...)` in JavaScript and
/// [DateTime.parse] in Dart read such a string as *device* time, so the
/// original app's forecasts were only correct when the phone happened to sit
/// in the same zone as the place being looked at. Check the weather in Tokyo
/// from California and every hour was labelled eight hours wrong.
///
/// This type is the fix: the response's `utc_offset_seconds` is captured, the
/// naive strings are resolved into true instants against it, and the UI
/// renders wall clock back through [wallClock] instead of the device zone.
final class ForecastTimeZone {
  const ForecastTimeZone({
    required this.name,
    required this.abbreviation,
    required this.utcOffset,
  });

  /// IANA name, e.g. `America/Los_Angeles`.
  final String name;

  /// Short form, e.g. `PDT`.
  final String abbreviation;

  final Duration utcOffset;

  /// The device's own zone, used when a response carries no offset.
  static ForecastTimeZone local() => ForecastTimeZone(
    name: 'local',
    abbreviation: 'local',
    utcOffset: DateTime.now().timeZoneOffset,
  );

  /// The wall clock at the forecast location for a given instant.
  ///
  /// Returned as a UTC-flagged [DateTime] whose *fields* are the local ones,
  /// which is the only way to carry a fixed-offset wall clock in core Dart
  /// without a time zone database. Read its components; do not read its
  /// epoch value.
  DateTime wallClock(DateTime instant) => instant.toUtc().add(utcOffset);

  @override
  String toString() => 'ForecastTimeZone($name, $abbreviation, $utcOffset)';
}

/// Conditions right now.
final class CurrentWeather {
  const CurrentWeather({
    required this.temp,
    required this.feelsLike,
    required this.code,
    required this.isDay,
    required this.humidity,
    required this.pressure,
    required this.windSpeed,
    required this.windDir,
    required this.windGust,
    required this.cloud,
    required this.precip,
    required this.uv,
    required this.visibility,
  });

  /// °F.
  final double temp;

  /// °F.
  final double feelsLike;

  /// WMO weather code.
  final int code;
  final bool isDay;

  /// Percent.
  final double humidity;

  /// hPa, mean sea level.
  final double pressure;

  /// mph.
  final double windSpeed;

  /// Degrees the wind blows *from*.
  final double windDir;

  /// mph.
  final double windGust;

  /// Percent cover.
  final double cloud;

  /// Inches.
  final double precip;

  final double uv;

  /// Metres.
  final double visibility;
}

/// One point on the 24-hour strip.
final class HourPoint {
  const HourPoint({
    required this.time,
    required this.temp,
    required this.code,
    required this.isDay,
    required this.precipProb,
    required this.windSpeed,
  });

  /// True instant, not a device-local reading of a naive string.
  final DateTime time;
  final double temp;
  final int code;
  final bool isDay;

  /// Percent.
  final double precipProb;

  /// mph.
  final double windSpeed;
}

/// One row of the 10-day forecast.
final class DayPoint {
  const DayPoint({
    required this.time,
    required this.code,
    required this.min,
    required this.max,
    required this.sunrise,
    required this.sunset,
    required this.uvMax,
    required this.precipProb,
    required this.windMax,
  });

  final DateTime time;
  final int code;
  final double min;
  final double max;
  final DateTime? sunrise;
  final DateTime? sunset;
  final double uvMax;
  final double precipProb;
  final double windMax;
}

/// A full weather load for one point.
final class WeatherData {
  const WeatherData({
    required this.position,
    required this.name,
    required this.timeZone,
    required this.current,
    required this.hourly,
    required this.daily,
    required this.weekMin,
    required this.weekMax,
  });

  final LngLat position;

  /// Reverse-geocoded label; never empty (falls back to `Current Location`).
  final String name;

  final ForecastTimeZone timeZone;
  final CurrentWeather current;
  final List<HourPoint> hourly;
  final List<DayPoint> daily;

  /// Coldest low and warmest high across [daily], for the 10-day range bars.
  ///
  /// **Null when [daily] is empty.** The original computed these with
  /// `Math.min(...[])`, which is `Infinity` rather than an error — the range
  /// bars then divided by an infinite span and every bar collapsed to a
  /// sliver, silently, with no clue as to why. Making the absence explicit
  /// forces the UI to decide what an empty forecast looks like.
  final double? weekMin;
  final double? weekMax;
}

/// One point on the surf strip.
final class SurfHour {
  const SurfHour({
    required this.time,
    required this.waveHeight,
    required this.wavePeriod,
    required this.swellHeight,
    required this.swellPeriod,
    required this.swellDir,
    required this.windSpeed,
    required this.windDir,
  });

  final DateTime time;

  /// Feet.
  final double waveHeight;

  /// Seconds.
  final double wavePeriod;

  /// Feet.
  final double swellHeight;

  /// Seconds.
  final double swellPeriod;

  /// Degrees the swell comes *from*.
  final double swellDir;

  /// mph. The marine endpoint carries no wind, so this is filled from the
  /// weather forecast when the two are loaded together, and is 0 otherwise.
  final double windSpeed;
  final double windDir;

  SurfHour withWind({required double speed, required double direction}) =>
      SurfHour(
        time: time,
        waveHeight: waveHeight,
        wavePeriod: wavePeriod,
        swellHeight: swellHeight,
        swellPeriod: swellPeriod,
        swellDir: swellDir,
        windSpeed: speed,
        windDir: direction,
      );
}

/// One row of the surf outlook.
final class SurfDay {
  const SurfDay({
    required this.time,
    required this.waveMax,
    required this.periodMax,
    required this.dirDominant,
  });

  final DateTime time;
  final double waveMax;
  final double periodMax;
  final double dirDominant;
}

/// Sea state right now.
final class MarineCurrent {
  const MarineCurrent({
    required this.waveHeight,
    required this.wavePeriod,
    required this.waveDir,
    required this.swellHeight,
    required this.swellPeriod,
    required this.swellDir,
    required this.waterTemp,
  });

  /// Feet.
  final double waveHeight;
  final double wavePeriod;
  final double waveDir;
  final double swellHeight;
  final double swellPeriod;
  final double swellDir;

  /// °F, or null where the model has no sea-surface temperature.
  final double? waterTemp;
}

/// A full marine load for one point.
final class MarineData {
  const MarineData({
    required this.timeZone,
    required this.current,
    required this.hourly,
    required this.daily,
  });

  final ForecastTimeZone timeZone;
  final MarineCurrent current;
  final List<SurfHour> hourly;
  final List<SurfDay> daily;
}
