import 'package:pe_core/pe_core.dart';

/// Classify an OSRM maneuver into one of the 13 [ManeuverKind]s.
///
/// Ported from `classify` in `src/routing.ts`. The ordering is load-bearing:
/// **type is checked before modifier**, so a `roundabout` carrying a `left`
/// modifier still classifies as a roundabout rather than a left turn. Only
/// once no type matches does the modifier decide, and `uturn` is matched by
/// substring (so both `uturn` and `sharp uturn` land there) while the rest are
/// exact.
///
/// Everything unmatched falls through to [ManeuverKind.straight], which is how
/// `turn`, `continue`, `new name`, `fork`, `end of road` and
/// `exit roundabout` are handled — they carry no distinguishing type here and
/// are described entirely by their modifier.
ManeuverKind classifyManeuver({String? type, String? modifier}) {
  final t = type ?? '';
  final m = modifier ?? '';

  if (t == 'depart') return ManeuverKind.depart;
  if (t == 'arrive') return ManeuverKind.arrive;
  if (t == 'roundabout' || t == 'rotary') return ManeuverKind.roundabout;
  if (t == 'merge') return ManeuverKind.merge;
  if (t == 'on ramp' || t == 'off ramp') return ManeuverKind.ramp;

  if (m.contains('uturn')) return ManeuverKind.uturn;
  if (m == 'left') return ManeuverKind.left;
  if (m == 'right') return ManeuverKind.right;
  if (m == 'slight left') return ManeuverKind.slightLeft;
  if (m == 'slight right') return ManeuverKind.slightRight;
  if (m == 'sharp left') return ManeuverKind.sharpLeft;
  if (m == 'sharp right') return ManeuverKind.sharpRight;

  return ManeuverKind.straight;
}

/// Build the human-readable instruction for a maneuver.
///
/// Ported from `describe` in `src/routing.ts`. Note the u-turn case uses
/// `" on <road>"` where every other road-bearing case uses `" onto <road>"` —
/// you make a U-turn *on* a street, not onto one. Arrival never names a road.
String describeManeuver(String? roadName, ManeuverKind kind) {
  final road = (roadName ?? '').trim();
  final onto = road.isEmpty ? '' : ' onto $road';
  final on = road.isEmpty ? '' : ' on $road';

  switch (kind) {
    case ManeuverKind.depart:
      return road.isEmpty ? 'Start' : 'Head out on $road';
    case ManeuverKind.arrive:
      return 'Arrive at your destination';
    case ManeuverKind.roundabout:
      return 'Enter the roundabout$onto';
    case ManeuverKind.merge:
      return 'Merge$onto';
    case ManeuverKind.ramp:
      return 'Take the ramp$onto';
    case ManeuverKind.uturn:
      return 'Make a U-turn$on';
    case ManeuverKind.left:
      return 'Turn left$onto';
    case ManeuverKind.right:
      return 'Turn right$onto';
    case ManeuverKind.slightLeft:
      return 'Slight left$onto';
    case ManeuverKind.slightRight:
      return 'Slight right$onto';
    case ManeuverKind.sharpLeft:
      return 'Sharp left$onto';
    case ManeuverKind.sharpRight:
      return 'Sharp right$onto';
    case ManeuverKind.straight:
      return road.isEmpty ? 'Continue straight' : 'Continue on $road';
  }
}

/// Thrown when an OSRM response cannot be used.
final class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;

  @override
  String toString() => 'RoutingException: $message';
}

/// Parse one OSRM route object.
///
/// Ported from `parseRoute` in `src/routing.ts`. Steps are flattened across
/// **all** legs — leg boundaries are not preserved, matching the original,
/// which is fine because the app routes point-to-point without waypoints.
///
/// Distances and durations default to 0 when absent. A route with no usable
/// geometry throws, rather than yielding a silently empty line.
RouteModel parseOsrmRoute(Map<String, dynamic> route) {
  final geometry = route['geometry'];
  if (geometry is! Map<String, dynamic>) {
    throw const RoutingException('route has no geometry');
  }
  final rawCoords = geometry['coordinates'];
  if (rawCoords is! List || rawCoords.isEmpty) {
    throw const RoutingException('route geometry has no coordinates');
  }

  final coordinates = <LngLat>[];
  for (final pair in rawCoords) {
    if (pair is List && pair.length >= 2) {
      final lon = pair[0];
      final lat = pair[1];
      if (lon is num && lat is num) {
        coordinates.add(LngLat(lon.toDouble(), lat.toDouble()));
      }
    }
  }
  if (coordinates.length < 2) {
    throw const RoutingException('route geometry is degenerate');
  }

  final steps = <RouteStep>[];
  final legs = route['legs'];
  if (legs is List) {
    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;
      final legSteps = leg['steps'];
      if (legSteps is! List) continue;
      for (final step in legSteps) {
        if (step is! Map<String, dynamic>) continue;
        final parsed = _parseStep(step);
        if (parsed != null) steps.add(parsed);
      }
    }
  }

  return RouteModel(
    coordinates: coordinates,
    steps: steps,
    distance: _asDouble(route['distance']) ?? 0,
    duration: _asDouble(route['duration']) ?? 0,
  );
}

/// Parse the full OSRM `/route` response into candidate routes.
///
/// The first entry is the primary route; the rest are alternates. Ported from
/// `fetchRoutes` in `src/routing.ts`, which rejects any response whose `code`
/// is not `Ok` or which carries no routes.
List<RouteModel> parseOsrmResponse(Map<String, dynamic> body) {
  final code = body['code'];
  final routes = body['routes'];
  if (code != 'Ok' || routes is! List || routes.isEmpty) {
    throw const RoutingException('No route found');
  }
  final out = <RouteModel>[];
  for (final route in routes) {
    if (route is! Map<String, dynamic>) continue;
    out.add(parseOsrmRoute(route));
  }
  if (out.isEmpty) throw const RoutingException('No route found');
  return out;
}

RouteStep? _parseStep(Map<String, dynamic> step) {
  final maneuver = step['maneuver'];
  if (maneuver is! Map<String, dynamic>) return null;

  final loc = maneuver['location'];
  if (loc is! List || loc.length < 2) return null;
  final lon = loc[0];
  final lat = loc[1];
  if (lon is! num || lat is! num) return null;

  final kind = classifyManeuver(
    type: maneuver['type'] as String?,
    modifier: maneuver['modifier'] as String?,
  );

  return RouteStep(
    instruction: describeManeuver(step['name'] as String?, kind),
    distance: _asDouble(step['distance']) ?? 0,
    location: LngLat(lon.toDouble(), lat.toDouble()),
    kind: kind,
  );
}

double? _asDouble(Object? v) => v is num ? v.toDouble() : null;
