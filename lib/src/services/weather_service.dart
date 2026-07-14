import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/geo_point.dart';
import '../models/weather.dart';

/// Open-Meteo current + hourly + daily forecast — free, keyless, and the
/// response already comes back in the site's local timezone when
/// `timezone=auto` is passed, which keeps sunrise/sunset & the 24h strip
/// sane without any client-side timezone math.
class WeatherService {
  WeatherService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  Future<WeatherSnapshot> fetch(GeoPoint point) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.openMeteoForecastUrl,
      queryParameters: {
        'latitude': point.latitude,
        'longitude': point.longitude,
        'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,'
            'weather_code,wind_speed_10m,wind_direction_10m,precipitation',
        'hourly': 'temperature_2m,weather_code,precipitation_probability,uv_index',
        'daily': 'temperature_2m_max,temperature_2m_min,weather_code,'
            'precipitation_probability_max,sunrise,sunset,uv_index_max',
        'timezone': 'auto',
        'forecast_days': 8,
      },
    );

    final data = response.data ?? const {};
    final current = data['current'] as Map<String, dynamic>? ?? const {};
    final hourly = data['hourly'] as Map<String, dynamic>? ?? const {};
    final daily = data['daily'] as Map<String, dynamic>? ?? const {};

    final now = DateTime.tryParse(current['time'] as String? ?? '') ?? DateTime.now();

    final hourlyTimes = ((hourly['time'] as List<dynamic>?) ?? const [])
        .map((t) => DateTime.parse(t as String))
        .toList();
    final hourlyTemps = ((hourly['temperature_2m'] as List<dynamic>?) ?? const [])
        .map((v) => (v as num).toDouble())
        .toList();
    final hourlyCodes =
        ((hourly['weather_code'] as List<dynamic>?) ?? const []).map((v) => (v as num).toInt()).toList();
    final hourlyPop = ((hourly['precipitation_probability'] as List<dynamic>?) ?? const [])
        .map((v) => (v as num).toInt())
        .toList();
    final hourlyUv =
        ((hourly['uv_index'] as List<dynamic>?) ?? const []).map((v) => (v as num).toDouble()).toList();

    int nearestHourIndex = 0;
    Duration best = const Duration(days: 999);
    for (var i = 0; i < hourlyTimes.length; i++) {
      final diff = hourlyTimes[i].difference(now).abs();
      if (diff < best) {
        best = diff;
        nearestHourIndex = i;
      }
    }

    final dailyDates =
        ((daily['time'] as List<dynamic>?) ?? const []).map((t) => DateTime.parse(t as String)).toList();
    final dailySunrise = ((daily['sunrise'] as List<dynamic>?) ?? const [])
        .map((t) => DateTime.tryParse(t as String) ?? now)
        .toList();
    final dailySunset = ((daily['sunset'] as List<dynamic>?) ?? const [])
        .map((t) => DateTime.tryParse(t as String) ?? now)
        .toList();

    final currentWeather = CurrentWeather(
      temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
      feelsLikeC: (current['apparent_temperature'] as num?)?.toDouble() ?? 0,
      condition: weatherConditionFromCode((current['weather_code'] as num?)?.toInt() ?? -1),
      windSpeedKmh: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
      windDirectionDeg: (current['wind_direction_10m'] as num?)?.toDouble() ?? 0,
      humidityPercent: (current['relative_humidity_2m'] as num?)?.toInt() ?? 0,
      uvIndex: hourlyUv.isNotEmpty ? hourlyUv[nearestHourIndex.clamp(0, hourlyUv.length - 1)] : 0,
      precipitationChancePercent:
          hourlyPop.isNotEmpty ? hourlyPop[nearestHourIndex.clamp(0, hourlyPop.length - 1)] : 0,
      isDay: ((current['is_day'] as num?)?.toInt() ?? 1) == 1,
      sunrise: dailySunrise.isNotEmpty ? dailySunrise.first : now,
      sunset: dailySunset.isNotEmpty ? dailySunset.first : now,
      observedAt: now,
    );

    final hourlyForecasts = <HourlyForecast>[];
    for (var i = nearestHourIndex; i < hourlyTimes.length && hourlyForecasts.length < 24; i++) {
      hourlyForecasts.add(
        HourlyForecast(
          time: hourlyTimes[i],
          temperatureC: hourlyTemps[i],
          condition: weatherConditionFromCode(hourlyCodes[i]),
          precipitationChancePercent: hourlyPop.length > i ? hourlyPop[i] : 0,
        ),
      );
    }

    final dailyMax = ((daily['temperature_2m_max'] as List<dynamic>?) ?? const [])
        .map((v) => (v as num).toDouble())
        .toList();
    final dailyMin = ((daily['temperature_2m_min'] as List<dynamic>?) ?? const [])
        .map((v) => (v as num).toDouble())
        .toList();
    final dailyCodes = ((daily['weather_code'] as List<dynamic>?) ?? const [])
        .map((v) => (v as num).toInt())
        .toList();
    final dailyPop = ((daily['precipitation_probability_max'] as List<dynamic>?) ?? const [])
        .map((v) => (v as num).toInt())
        .toList();

    final dailyForecasts = <DailyForecast>[
      for (var i = 0; i < dailyDates.length; i++)
        DailyForecast(
          date: dailyDates[i],
          highC: dailyMax.length > i ? dailyMax[i] : 0,
          lowC: dailyMin.length > i ? dailyMin[i] : 0,
          condition: weatherConditionFromCode(dailyCodes.length > i ? dailyCodes[i] : -1),
          precipitationChancePercent: dailyPop.length > i ? dailyPop[i] : 0,
        ),
    ];

    return WeatherSnapshot(
      current: currentWeather,
      hourly: hourlyForecasts,
      daily: dailyForecasts,
      fetchedForLat: point.latitude,
      fetchedForLng: point.longitude,
    );
  }
}
