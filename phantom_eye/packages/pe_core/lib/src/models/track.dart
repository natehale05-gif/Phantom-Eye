import '../geo/lng_lat.dart';

/// A recorded GPS track.
///
/// The legacy app drew the live breadcrumb through `globe.beginTrack()` /
/// `pushTrackPoint()` and never persisted it — stopping a recording showed
/// `Track saved · 2.4 mi` and then dropped the geometry on the next reload.
/// Modelling it here is what makes saving it possible; the store that writes
/// it belongs to a later increment, so nothing is claimed about persistence
/// yet.
final class RecordedTrack {
  const RecordedTrack({
    required this.id,
    required this.startedAt,
    required this.points,
    required this.distanceMeters,
    this.endedAt,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Every fix accepted into the track, in order.
  final List<LngLat> points;

  /// Ground distance along [points], in metres.
  final double distanceMeters;

  Duration get elapsed => (endedAt ?? DateTime.now()).difference(startedAt);

  static RecordedTrack? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final startedAt = json['startedAt'];
    if (id is! String || id.isEmpty || startedAt is! String) return null;
    final started = DateTime.tryParse(startedAt);
    if (started == null) return null;

    final rawPoints = json['points'];
    final points = <LngLat>[];
    if (rawPoints is List) {
      for (final pair in rawPoints) {
        if (pair is List && pair.length >= 2) {
          final lon = pair[0];
          final lat = pair[1];
          if (lon is num && lat is num && lon.isFinite && lat.isFinite) {
            points.add(LngLat(lon.toDouble(), lat.toDouble()));
          }
        }
      }
    }

    final ended = json['endedAt'];
    final distance = json['distanceMeters'];
    return RecordedTrack(
      id: id,
      startedAt: started,
      endedAt: ended is String ? DateTime.tryParse(ended) : null,
      points: points,
      distanceMeters: distance is num ? distance.toDouble() : 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': ?endedAt?.toIso8601String(),
    'points': [
      for (final p in points) [p.lon, p.lat],
    ],
    'distanceMeters': distanceMeters,
  };

  @override
  String toString() =>
      'RecordedTrack($id, ${points.length} pts, ${distanceMeters.round()} m)';
}
