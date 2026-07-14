import 'dart:math' as math;

import '../../models/unit_system.dart';

/// Human-readable formatting for distance/duration/speed/elevation, shared
/// by the map HUD, route preview, weather panel, and track summaries.
abstract final class Formatters {
  static String distance(double meters, UnitSystem units, {bool short = false}) {
    if (units.isImperial) {
      final feet = meters * 3.28084;
      if (feet < 528) {
        return '${feet.round()} ft';
      }
      final miles = feet / 5280;
      return '${_trim(miles)} ${short ? 'mi' : (miles == 1 ? 'mile' : 'miles')}';
    } else {
      if (meters < 1000) {
        return '${meters.round()} m';
      }
      final km = meters / 1000;
      return '${_trim(km)} km';
    }
  }

  static String elevation(double meters, UnitSystem units) {
    if (units.isImperial) {
      final feet = meters * 3.28084;
      return '${feet.round()} ft';
    }
    return '${meters.round()} m';
  }

  static String speed(double metersPerSecond, UnitSystem units) {
    if (units.isImperial) {
      final mph = metersPerSecond * 2.23694;
      return '${mph.round()} mph';
    }
    final kmh = metersPerSecond * 3.6;
    return '${kmh.round()} km/h';
  }

  static String temperature(double celsius, UnitSystem units) {
    if (units.isImperial) {
      final f = celsius * 9 / 5 + 32;
      return '${f.round()}°';
    }
    return '${celsius.round()}°';
  }

  static String duration(Duration d) {
    final totalMinutes = (d.inSeconds / 60).round();
    if (totalMinutes < 1) return '<1 min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes min';
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }

  /// Compact clock-style ETA, e.g. "5:42 PM".
  static String etaClock(DateTime arrival) {
    final hour24 = arrival.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = arrival.minute.toString().padLeft(2, '0');
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $suffix';
  }

  static String compassDirection(double bearingDeg) {
    const dirs = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final ix = (((bearingDeg % 360) / 22.5) + 0.5).floor() % 16;
    return dirs[ix];
  }

  static String _trim(double value) {
    if (value >= 100) return value.round().toString();
    if (value >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(1);
  }

  static double metersFromFeet(double feet) => feet / 3.28084;
  static double celsiusFromFahrenheit(double f) => (f - 32) * 5 / 9;

  static String relativeTime(DateTime from, DateTime now) {
    final diff = now.difference(from);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static double round1(double v) => (v * 10).round() / 10;
  static double clamp01(double v) => math.min(1.0, math.max(0.0, v));
}
