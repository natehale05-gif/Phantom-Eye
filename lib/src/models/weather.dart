/// Open-Meteo weather models. Open-Meteo's WMO weather codes map is fixed
/// and documented at https://open-meteo.com/en/docs — reproduced here to
/// pick an SF-Symbols-style Material icon + short label per code.
enum WeatherCondition {
  clear,
  mainlyClear,
  partlyCloudy,
  overcast,
  fog,
  drizzle,
  rain,
  freezingRain,
  snow,
  snowGrains,
  rainShowers,
  snowShowers,
  thunderstorm,
  unknown,
}

WeatherCondition weatherConditionFromCode(int code) {
  switch (code) {
    case 0:
      return WeatherCondition.clear;
    case 1:
    case 2:
      return WeatherCondition.mainlyClear;
    case 3:
      return WeatherCondition.overcast;
    case 45:
    case 48:
      return WeatherCondition.fog;
    case 51:
    case 53:
    case 55:
    case 56:
    case 57:
      return WeatherCondition.drizzle;
    case 61:
    case 63:
    case 65:
      return WeatherCondition.rain;
    case 66:
    case 67:
      return WeatherCondition.freezingRain;
    case 71:
    case 73:
    case 75:
    case 77:
      return WeatherCondition.snow;
    case 80:
    case 81:
    case 82:
      return WeatherCondition.rainShowers;
    case 85:
    case 86:
      return WeatherCondition.snowShowers;
    case 95:
    case 96:
    case 99:
      return WeatherCondition.thunderstorm;
    default:
      return WeatherCondition.unknown;
  }
}

extension WeatherConditionX on WeatherCondition {
  String get label => switch (this) {
        WeatherCondition.clear => 'Clear',
        WeatherCondition.mainlyClear => 'Mostly Clear',
        WeatherCondition.partlyCloudy => 'Partly Cloudy',
        WeatherCondition.overcast => 'Overcast',
        WeatherCondition.fog => 'Fog',
        WeatherCondition.drizzle => 'Drizzle',
        WeatherCondition.rain => 'Rain',
        WeatherCondition.freezingRain => 'Freezing Rain',
        WeatherCondition.snow => 'Snow',
        WeatherCondition.snowGrains => 'Snow Grains',
        WeatherCondition.rainShowers => 'Showers',
        WeatherCondition.snowShowers => 'Snow Showers',
        WeatherCondition.thunderstorm => 'Thunderstorm',
        WeatherCondition.unknown => 'Weather',
      };
}

class CurrentWeather {
  const CurrentWeather({
    required this.temperatureC,
    required this.feelsLikeC,
    required this.condition,
    required this.windSpeedKmh,
    required this.windDirectionDeg,
    required this.humidityPercent,
    required this.uvIndex,
    required this.precipitationChancePercent,
    required this.isDay,
    required this.sunrise,
    required this.sunset,
    required this.observedAt,
  });

  final double temperatureC;
  final double feelsLikeC;
  final WeatherCondition condition;
  final double windSpeedKmh;
  final double windDirectionDeg;
  final int humidityPercent;
  final double uvIndex;
  final int precipitationChancePercent;
  final bool isDay;
  final DateTime sunrise;
  final DateTime sunset;
  final DateTime observedAt;
}

class HourlyForecast {
  const HourlyForecast({
    required this.time,
    required this.temperatureC,
    required this.condition,
    required this.precipitationChancePercent,
  });

  final DateTime time;
  final double temperatureC;
  final WeatherCondition condition;
  final int precipitationChancePercent;
}

class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.highC,
    required this.lowC,
    required this.condition,
    required this.precipitationChancePercent,
  });

  final DateTime date;
  final double highC;
  final double lowC;
  final WeatherCondition condition;
  final int precipitationChancePercent;
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.current,
    required this.hourly,
    required this.daily,
    required this.fetchedForLat,
    required this.fetchedForLng,
  });

  final CurrentWeather current;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;
  final double fetchedForLat;
  final double fetchedForLng;
}
