import 'package:uuid/uuid.dart';

import 'geo_point.dart';
import 'place.dart';

const _uuid = Uuid();

enum WaypointIcon { pin, flag, camera, water, campsite, danger, gate, summit, parking, tree }

class Waypoint {
  Waypoint({
    String? id,
    required this.name,
    required this.point,
    this.icon = WaypointIcon.pin,
    this.notes,
    this.elevationMeters,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final GeoPoint point;
  final WaypointIcon icon;
  final String? notes;
  final double? elevationMeters;
  final DateTime createdAt;

  Place toPlace() => Place(name: name, point: point, category: PlaceCategory.other);

  Waypoint copyWith({String? name, WaypointIcon? icon, String? notes}) => Waypoint(
        id: id,
        name: name ?? this.name,
        point: point,
        icon: icon ?? this.icon,
        notes: notes ?? this.notes,
        elevationMeters: elevationMeters,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': point.latitude,
        'lng': point.longitude,
        'icon': icon.name,
        'notes': notes,
        'elevationMeters': elevationMeters,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
        id: json['id'] as String,
        name: json['name'] as String,
        point: GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        icon: WaypointIcon.values.firstWhere(
          (e) => e.name == json['icon'],
          orElse: () => WaypointIcon.pin,
        ),
        notes: json['notes'] as String?,
        elevationMeters: (json['elevationMeters'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
