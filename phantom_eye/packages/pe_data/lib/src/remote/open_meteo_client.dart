import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pe_core/pe_core.dart';

import '../parse/open_meteo_parser.dart';

const String kOpenMeteoForecastUrl = 'https://api.open-meteo.com/v1/forecast';
const String kOpenMeteoMarineUrl =
    'https://marine-api.open-meteo.com/v1/marine';

/// Variables requested from the forecast endpoint.
///
/// Ported verbatim from `src/weather.ts:113`. These are kept as named
/// constants rather than inlined because every one of them backs a specific
/// tile in the weather page — dropping one silently blanks that tile.
const String kCurrentVariables =
    'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,'
    'precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,'
    'wind_direction_10m,wind_gusts_10m';

const String kHourlyVariables =
    'temperature_2m,weather_code,precipitation_probability,wind_speed_10m,'
    'is_day,uv_index,visibility';

const String kDailyVariables =
    'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,'
    'uv_index_max,precipitation_probability_max,wind_speed_10m_max';

const String kMarineCurrentVariables =
    'wave_height,wave_direction,wave_period,swell_wave_height,'
    'swell_wave_period,swell_wave_direction,sea_surface_temperature';

const String kMarineHourlyVariables =
    'wave_height,wave_period,wave_direction,swell_wave_height,'
    'swell_wave_period,swell_wave_direction';

const String kMarineDailyVariables =
    'wave_height_max,wave_period_max,wave_direction_dominant';

/// Days requested from each endpoint.
const int kForecastDays = 10;
const int kMarineForecastDays = 7;

/// Weather and marine data from Open-Meteo.
///
/// `timezone=auto` is requested so timestamps come back as wall clock at the
/// forecast location; [parseForecastTimeZone] captures the offset that makes
/// them resolvable. See [ForecastTimeZone] for why that matters.
final class OpenMeteoClient {
  OpenMeteoClient({
    http.Client? client,
    this.forecastUrl = kOpenMeteoForecastUrl,
    this.marineUrl = kOpenMeteoMarineUrl,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final String forecastUrl;
  final String marineUrl;
  final DateTime Function() _clock;

  /// Just enough to paint the at-a-glance weather chip.
  Future<({double temp, int code, bool isDay})> currentBrief(LngLat at) async {
    final body = await _get(forecastUrl, {
      'latitude': '${at.lat}',
      'longitude': '${at.lon}',
      'current': 'temperature_2m,weather_code,is_day',
      'temperature_unit': 'fahrenheit',
    }, 'Weather failed');
    return parseCurrentBrief(body);
  }

  /// The full weather page load.
  ///
  /// [name] is the already-resolved display label; reverse geocoding is a
  /// separate concern and lives in `ReverseGeocoder`. The original called it
  /// from inside the fetch, which meant a slow geocoder delayed the forecast
  /// even though the two are independent.
  Future<WeatherData> forecast(LngLat at, {required String name}) async {
    final body = await _get(forecastUrl, {
      'latitude': '${at.lat}',
      'longitude': '${at.lon}',
      'current': kCurrentVariables,
      'hourly': kHourlyVariables,
      'daily': kDailyVariables,
      'temperature_unit': 'fahrenheit',
      'wind_speed_unit': 'mph',
      'precipitation_unit': 'inch',
      'timezone': 'auto',
      'forecast_days': '$kForecastDays',
    }, 'Weather failed');
    return parseForecast(body, position: at, name: name, now: _clock());
  }

  /// The surf report. Throws [WeatherException] for a point with no marine
  /// coverage, which is how an inland tap is rejected.
  Future<MarineData> marine(LngLat at) async {
    final body = await _get(marineUrl, {
      'latitude': '${at.lat}',
      'longitude': '${at.lon}',
      'current': kMarineCurrentVariables,
      'hourly': kMarineHourlyVariables,
      'daily': kMarineDailyVariables,
      'timezone': 'auto',
      'length_unit': 'imperial',
      'forecast_days': '$kMarineForecastDays',
    }, 'No marine data');
    return parseMarine(body, now: _clock());
  }

  Future<Map<String, dynamic>> _get(
    String url,
    Map<String, String> params,
    String failureMessage,
  ) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse(url).replace(queryParameters: params),
      );
    } on http.ClientException catch (e) {
      throw WeatherException('$failureMessage (${e.message})');
    }
    if (response.statusCode != 200) {
      throw WeatherException('$failureMessage (${response.statusCode})');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } on FormatException {
      throw WeatherException('$failureMessage (invalid response)');
    }
    if (decoded is! Map<String, dynamic>) {
      throw WeatherException('$failureMessage (unexpected response)');
    }
    return decoded;
  }

  void close() => _client.close();
}
