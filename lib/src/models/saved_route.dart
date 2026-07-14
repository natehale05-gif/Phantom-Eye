import 'package:uuid/uuid.dart';

import 'geo_point.dart';
import 'route_result.dart';

const _uuid = Uuid();

/// A route persisted into the "Routes" library — either saved from a
/// planned A→B route or from the custom route builder.
class SavedRoute {
  SavedRoute({
    String? id,
    required this.name,
    required this.path,
    required this.profile,
    required this.distanceMeters,
    required this.durationSeconds,
    this.elevationGainMeters = 0,
    this.elevationLossMeters = 0,
    this.waypointNames = const [],
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final List<GeoPoint> path;
  final TravelProfile profile;
  final double distanceMeters;
  final double durationSeconds;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final List<String> waypointNames;
  final DateTime createdAt;

  factory SavedRoute.fromRouteResult(String name, RouteResult route, {List<String> waypointNames = const []}) {
    return SavedRoute(
      name: name,
      path: route.path,
      profile: route.profile,
      distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      elevationGainMeters: route.elevationGainMeters ?? 0,
      elevationLossMeters: route.elevationLossMeters ?? 0,
      waypointNames: waypointNames,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'profile': profile.name,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'elevationGainMeters': elevationGainMeters,
        'elevationLossMeters': elevationLossMeters,
        'waypointNames': waypointNames,
        'createdAt': createdAt.toIso8601String(),
        'path': path.map((p) => [p.latitude, p.longitude]).toList(),
      };

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
        id: json['id'] as String,
        name: json['name'] as String,
        profile: TravelProfile.values.firstWhere(
          (e) => e.name == json['profile'],
          orElse: () => TravelProfile.drive,
        ),
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
        elevationGainMeters: (json['elevationGainMeters'] as num?)?.toDouble() ?? 0,
        elevationLossMeters: (json['elevationLossMeters'] as num?)?.toDouble() ?? 0,
        waypointNames: ((json['waypointNames'] as List<dynamic>?) ?? const []).cast<String>(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        path: ((json['path'] as List<dynamic>?) ?? const [])
            .map((raw) {
              final pair = raw as List<dynamic>;
              return GeoPoint((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
            })
            .toList(),
      );
}
