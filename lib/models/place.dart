/// A curated destination with a hand-tuned cinematic camera framing.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.region,
    required this.lon,
    required this.lat,
    required this.height,
    required this.heading,
    required this.pitch,
  });

  final String id;
  final String name;
  final String region;

  /// Longitude / latitude in degrees.
  final double lon;
  final double lat;

  /// Camera height above the target in meters, plus heading/pitch in degrees.
  final double height;
  final double heading;
  final double pitch;
}
