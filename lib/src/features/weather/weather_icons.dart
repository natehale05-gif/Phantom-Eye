import 'package:flutter/material.dart';

import '../../models/weather.dart';

/// Maps Open-Meteo WMO weather codes (already bucketed into
/// [WeatherCondition]) to Material icons — the closest built-in
/// equivalent to SF Symbols' weather glyph set, since bundling a full
/// custom icon font wasn't worth it for this build.
IconData weatherIconFor(WeatherCondition condition, {bool isDay = true}) {
  switch (condition) {
    case WeatherCondition.clear:
      return isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
    case WeatherCondition.mainlyClear:
      return isDay ? Icons.wb_twilight_rounded : Icons.nights_stay_rounded;
    case WeatherCondition.partlyCloudy:
      return isDay ? Icons.wb_cloudy_rounded : Icons.cloud_rounded;
    case WeatherCondition.overcast:
      return Icons.cloud_rounded;
    case WeatherCondition.fog:
      return Icons.foggy;
    case WeatherCondition.drizzle:
      return Icons.grain_rounded;
    case WeatherCondition.rain:
    case WeatherCondition.rainShowers:
      return Icons.water_drop_rounded;
    case WeatherCondition.freezingRain:
      return Icons.ac_unit_rounded;
    case WeatherCondition.snow:
    case WeatherCondition.snowGrains:
    case WeatherCondition.snowShowers:
      return Icons.ac_unit_rounded;
    case WeatherCondition.thunderstorm:
      return Icons.thunderstorm_rounded;
    case WeatherCondition.unknown:
      return Icons.help_outline_rounded;
  }
}
