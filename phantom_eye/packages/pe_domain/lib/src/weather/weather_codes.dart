import 'dart:math' as math;

/// The icon set the weather page draws from.
///
/// Mirrors `IconKey` in `src/weather.ts:300`.
enum WeatherIcon {
  clearDay,
  clearNight,
  partlyDay,
  partlyNight,
  cloudy,
  fog,
  drizzle,
  rain,
  sleet,
  snow,
  thunder,
}

/// A WMO code rendered as a label and an icon.
final class WeatherCondition {
  const WeatherCondition(this.label, this.icon);
  final String label;
  final WeatherIcon icon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeatherCondition && other.label == label && other.icon == icon);

  @override
  int get hashCode => Object.hash(label, icon);

  @override
  String toString() => 'WeatherCondition($label, $icon)';
}

/// Map a WMO weather code to its label and icon.
///
/// Ported from `wmo` in `src/weather.ts:313`. Unknown codes fall back to
/// `Cloudy` rather than throwing — Open-Meteo has added codes over time and a
/// forecast must never fail to render because of one.
WeatherCondition wmoCondition(int code, {bool isDay = true}) {
  WeatherIcon dayNight(WeatherIcon day, WeatherIcon night) =>
      isDay ? day : night;

  switch (code) {
    case 0:
      return WeatherCondition(
        'Clear',
        dayNight(WeatherIcon.clearDay, WeatherIcon.clearNight),
      );
    case 1:
      return WeatherCondition(
        'Mostly Clear',
        dayNight(WeatherIcon.clearDay, WeatherIcon.clearNight),
      );
    case 2:
      return WeatherCondition(
        'Partly Cloudy',
        dayNight(WeatherIcon.partlyDay, WeatherIcon.partlyNight),
      );
    case 3:
      return const WeatherCondition('Cloudy', WeatherIcon.cloudy);
    case 45:
    case 48:
      return const WeatherCondition('Fog', WeatherIcon.fog);
    case 51:
    case 53:
    case 55:
      return const WeatherCondition('Drizzle', WeatherIcon.drizzle);
    case 56:
    case 57:
      return const WeatherCondition('Freezing Drizzle', WeatherIcon.sleet);
    case 61:
    case 63:
    case 65:
      return const WeatherCondition('Rain', WeatherIcon.rain);
    case 66:
    case 67:
      return const WeatherCondition('Freezing Rain', WeatherIcon.sleet);
    case 71:
    case 73:
    case 75:
    case 77:
      return const WeatherCondition('Snow', WeatherIcon.snow);
    case 80:
    case 81:
    case 82:
      return const WeatherCondition('Showers', WeatherIcon.rain);
    case 85:
    case 86:
      return const WeatherCondition('Snow Showers', WeatherIcon.snow);
    case 95:
    case 96:
    case 99:
      return const WeatherCondition('Thunderstorm', WeatherIcon.thunder);
    default:
      return const WeatherCondition('Cloudy', WeatherIcon.cloudy);
  }
}

const List<String> kCompassPoints = [
  'N',
  'NNE',
  'NE',
  'ENE',
  'E',
  'ESE',
  'SE',
  'SSE',
  'S',
  'SSW',
  'SW',
  'WSW',
  'W',
  'WNW',
  'NW',
  'NNW',
];

/// A bearing as a 16-point compass label.
///
/// Ported from `compass` in `src/weather.ts:364`. The extra `% 16` after
/// rounding is what keeps 349°–360° from indexing off the end of the table;
/// the leading `% 360` here is made to handle negative bearings too, which
/// the original's `%` would have turned into a negative index.
String compassPoint(double degrees) {
  final normalized = ((degrees % 360) + 360) % 360;
  return kCompassPoints[(normalized / 22.5).round() % 16];
}

/// Where the wind sits relative to the incoming swell.
enum WindRelation { offshore, onshore, cross }

/// Classify wind against swell.
///
/// Ported from `windRelation` in `src/weather.ts:387`. Both angles are
/// directions the energy comes *from*, so wind and swell arriving from
/// opposite sides (delta near 180°) means the wind blows off the land and
/// back out against the waves — offshore, the good case.
WindRelation windRelation(double windFromDeg, double swellFromDeg) {
  final delta = ((windFromDeg - swellFromDeg + 540) % 360 - 180).abs();
  if (delta > 135) return WindRelation.offshore;
  if (delta < 45) return WindRelation.onshore;
  return WindRelation.cross;
}

/// A surf session scored out of 10.
final class SurfRating {
  const SurfRating(this.label, this.score, this.colorHex);
  final String label;
  final double score;
  final String colorHex;

  @override
  String toString() => 'SurfRating($label, ${score.toStringAsFixed(2)})';
}

/// Score the surf from swell size, period and wind.
///
/// Ported from `surfRating` in `src/weather.ts:369`. Size and period each
/// contribute up to 3, wind direction up to 2, and chop subtracts up to 2 —
/// so the ceiling is 8 in practice and `Epic` at 7.5 is genuinely rare.
SurfRating surfRating({
  required double swellFt,
  required double periodS,
  required double windMph,
  required WindRelation relation,
}) {
  var score = 0.0;
  score += math.min(swellFt / 2, 3);
  score += math.min(math.max(periodS - 6, 0) / 3, 3);
  score += switch (relation) {
    WindRelation.offshore => 2,
    WindRelation.cross => 1,
    WindRelation.onshore => 0,
  };
  score -= math.min(windMph / 12, 2);
  score = math.max(0, math.min(10, score));

  if (score >= 7.5) return SurfRating('Epic', score, '#30D158');
  if (score >= 5.5) return SurfRating('Good', score, '#34C759');
  if (score >= 3.5) return SurfRating('Fair', score, '#FFD60A');
  return SurfRating('Poor', score, '#FF9F0A');
}
