import 'package:uuid/uuid.dart';

import 'geo_point.dart';

const _uuid = Uuid();

/// A user-recorded GPS breadcrumb trail (onX/Gaia "track recording").
/// Distinct from [RouteResult], which is a *planned* path from a routing
/// engine — a Track is the ground-truth path actually walked/driven/ridden.
class Track {
  Track({
    String? id,
    required this.name,
    required this.points,
    required this.startedAt,
    required this.endedAt,
    this.distanceMeters = 0,
    this.elevationGainMeters = 0,
    this.elevationLossMeters = 0,
  }) : id = id ?? _uuid.v4();

  final String id;
  final String name;
  final List<TimedPoint> points;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final double elevationGainMeters;
  final double elevationLossMeters;

  Duration get duration => endedAt.difference(startedAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'distanceMeters': distanceMeters,
        'elevationGainMeters': elevationGainMeters,
        'elevationLossMeters': elevationLossMeters,
        'points': points
            .map((p) => {
                  'lat': p.point.latitude,
                  'lng': p.point.longitude,
                  't': p.timestamp.toIso8601String(),
                  'ele': p.elevationMeters,
                  'speed': p.speedMps,
                  'heading': p.headingDeg,
                })
            .toList(),
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        name: json['name'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: DateTime.parse(json['endedAt'] as String),
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
        elevationGainMeters: (json['elevationGainMeters'] as num?)?.toDouble() ?? 0,
        elevationLossMeters: (json['elevationLossMeters'] as num?)?.toDouble() ?? 0,
        points: ((json['points'] as List<dynamic>?) ?? const [])
            .map((raw) {
              final p = raw as Map<String, dynamic>;
              return TimedPoint(
                GeoPoint((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
                DateTime.parse(p['t'] as String),
                speedMps: (p['speed'] as num?)?.toDouble(),
                headingDeg: (p['heading'] as num?)?.toDouble(),
                elevationMeters: (p['ele'] as num?)?.toDouble(),
              );
            })
            .toList(),
      );
}
