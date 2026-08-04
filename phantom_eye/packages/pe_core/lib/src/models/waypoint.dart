import '../geo/lng_lat.dart';

/// A user-saved point on the map.
///
/// Mirrors the `Waypoint` interface in `src/field.ts:17`. The JSON shape is
/// kept byte-compatible with what the legacy app wrote to `localStorage`
/// (`lon`/`lat` as separate keys, `color`/`icon` optional), so a migration can
/// read existing saved waypoints rather than losing them.
final class Waypoint {
  const Waypoint({
    required this.id,
    required this.position,
    required this.label,
    this.colorHex,
    this.iconId,
  });

  final String id;
  final LngLat position;
  final String label;

  /// Null means "use the default" — stored as absent, matching the original.
  final String? colorHex;
  final String? iconId;

  /// Parse one stored entry, or null if it is not usable.
  ///
  /// Returning null rather than throwing is what lets a corrupt entry be
  /// dropped while the rest of the list survives. The legacy loader checked
  /// only that the outer value was an array and handed back whatever was
  /// inside, so a single truncated write produced a waypoint with no
  /// coordinate that broke rendering for the whole list.
  static Waypoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final lon = json['lon'];
    final lat = json['lat'];
    if (id is! String || id.isEmpty) return null;
    if (lon is! num || lat is! num) return null;
    if (!lon.isFinite || !lat.isFinite) return null;
    return Waypoint(
      id: id,
      position: LngLat(lon.toDouble(), lat.toDouble()),
      label: json['label'] is String ? json['label'] as String : '',
      colorHex: json['color'] is String ? json['color'] as String : null,
      iconId: json['icon'] is String ? json['icon'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'lon': position.lon,
    'lat': position.lat,
    'label': label,
    'color': ?colorHex,
    'icon': ?iconId,
  };

  Waypoint copyWith({String? label, String? colorHex, String? iconId}) =>
      Waypoint(
        id: id,
        position: position,
        label: label ?? this.label,
        colorHex: colorHex ?? this.colorHex,
        iconId: iconId ?? this.iconId,
      );

  @override
  String toString() => 'Waypoint($id, $label @ $position)';
}
