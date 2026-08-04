import '../geo/lng_lat.dart';

/// A curated destination with a hand-tuned camera framing.
///
/// Mirrors `Place` in `src/places.ts`. These are the iconic locations with
/// full photorealistic 3D coverage, each framed for a cinematic arrival —
/// which is why the camera parameters travel with the coordinate rather than
/// being derived. Flying to one with a default overhead camera looks nothing
/// like the intended shot.
final class CuratedPlace {
  const CuratedPlace({
    required this.id,
    required this.name,
    required this.region,
    required this.position,
    required this.cameraHeightMeters,
    required this.headingDegrees,
    required this.pitchDegrees,
  });

  final String id;
  final String name;

  /// Secondary label, e.g. `New York City` under `Manhattan`.
  final String region;

  final LngLat position;

  /// Camera height above the target, in metres.
  final double cameraHeightMeters;

  final double headingDegrees;

  /// Negative values look down; every curated framing is a downward angle.
  final double pitchDegrees;

  @override
  String toString() => 'CuratedPlace($id, $name)';
}
