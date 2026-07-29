import '../geo/lng_lat.dart';

/// A single GPS reading.
///
/// Mirrors the shape the legacy `src/geoloc.ts` produced from
/// `Geolocation.watchPosition`. Every optional field is genuinely optional on
/// real hardware — `heading` and `speed` are frequently null when stationary,
/// which the navigation logic must tolerate.
final class LocationFix {
  const LocationFix({
    required this.position,
    required this.timestamp,
    this.accuracy,
    this.heading,
    this.speed,
    this.altitude,
  });

  final LngLat position;
  final DateTime timestamp;

  /// Horizontal accuracy radius in metres.
  final double? accuracy;

  /// Course over ground in degrees, if the device reports it.
  final double? heading;

  /// Ground speed in m/s, if the device reports it.
  final double? speed;

  final double? altitude;

  /// Accuracy clamped the way the legacy location puck did it: never smaller
  /// than 4 m, defaulting to 8 m when the platform reports nothing.
  double get displayAccuracy {
    final a = accuracy;
    return a == null ? 8 : (a < 4 ? 4 : a);
  }
}
