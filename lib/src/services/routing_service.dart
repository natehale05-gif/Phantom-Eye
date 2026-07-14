import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../core/geo/polyline_codec.dart';
import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/geo_point.dart';
import '../models/route_result.dart';

/// Multi-leg route request: an ordered list of stops (origin, any
/// waypoints, destination) — used both by turn-by-turn A→B routing and by
/// the custom route builder (each new dropped waypoint re-requests the
/// whole chain).
class RoutingService {
  RoutingService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  /// Tries Valhalla first (best multi-profile support — needed for
  /// Walk/Bike trail routing), falls back to OSRM (driving only on the
  /// public demo server), and finally falls back to a straight-line
  /// estimate so the app *never* fails to produce a route, even fully
  /// offline (the straight-line leg just won't be very useful without a
  /// road/trail network, but the distance/ETA readout still works).
  Future<RouteResult> route(List<GeoPoint> stops, TravelProfile profile) async {
    if (stops.length < 2) {
      throw ArgumentError('Routing requires at least 2 stops');
    }

    try {
      return await _routeValhalla(stops, profile);
    } catch (e) {
      developer.log('Valhalla routing failed, falling back to OSRM', error: e, name: 'RoutingService');
    }

    if (profile == TravelProfile.drive) {
      try {
        return await _routeOsrm(stops, profile);
      } catch (e) {
        developer.log('OSRM routing failed, falling back to straight line', error: e, name: 'RoutingService');
      }
    }

    return _straightLineRoute(stops, profile);
  }

  Future<RouteResult> _routeValhalla(List<GeoPoint> stops, TravelProfile profile) async {
    final body = {
      'locations': stops.map((s) => {'lat': s.latitude, 'lon': s.longitude}).toList(),
      'costing': profile.valhallaCosting,
      'units': 'kilometers',
      'directions_options': {'units': 'kilometers'},
    };

    final response = await _dio.get<Map<String, dynamic>>(
      '${ApiEndpoints.valhallaBaseUrl}/route',
      queryParameters: {'json': jsonEncode(body)},
    );

    final trip = response.data?['trip'] as Map<String, dynamic>?;
    if (trip == null) throw StateError('Valhalla returned no trip');

    final legs = (trip['legs'] as List<dynamic>?) ?? const [];
    if (legs.isEmpty) throw StateError('Valhalla returned no legs');

    final path = <GeoPoint>[];
    final maneuvers = <RouteManeuver>[];

    for (final legRaw in legs) {
      final leg = legRaw as Map<String, dynamic>;
      final shape = leg['shape'] as String? ?? '';
      final legPath = PolylineCodec.decode(shape, precision: 6);
      final startIndex = path.length;
      path.addAll(legPath);

      final legManeuvers = (leg['maneuvers'] as List<dynamic>?) ?? const [];
      for (final mRaw in legManeuvers) {
        final m = mRaw as Map<String, dynamic>;
        final shapeIndex = (m['begin_shape_index'] as num?)?.toInt() ?? 0;
        final pointIndex = (startIndex + shapeIndex).clamp(0, path.length - 1);
        maneuvers.add(
          RouteManeuver(
            type: _valhallaManeuverType((m['type'] as num?)?.toInt() ?? 0),
            instruction: (m['instruction'] as String?) ?? 'Continue',
            point: path[pointIndex],
            distanceMeters: ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
            streetName: ((m['street_names'] as List<dynamic>?)?.cast<String>().join('/')),
          ),
        );
      }
    }

    final summary = trip['summary'] as Map<String, dynamic>? ?? const {};
    return RouteResult(
      profile: profile,
      source: RouteSource.valhalla,
      path: path,
      maneuvers: maneuvers,
      distanceMeters: ((summary['length'] as num?)?.toDouble() ?? 0) * 1000,
      durationSeconds: (summary['time'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<RouteResult> _routeOsrm(List<GeoPoint> stops, TravelProfile profile) async {
    final coords = stops.map((s) => '${s.longitude},${s.latitude}').join(';');
    final response = await _dio.get<Map<String, dynamic>>(
      '${ApiEndpoints.osrmBaseUrl}/route/v1/${profile.osrmProfile}/$coords',
      queryParameters: {'overview': 'full', 'geometries': 'polyline', 'steps': 'true'},
    );

    final routes = (response.data?['routes'] as List<dynamic>?) ?? const [];
    if (routes.isEmpty) throw StateError('OSRM returned no routes');
    final route = routes.first as Map<String, dynamic>;
    final path = PolylineCodec.decode(route['geometry'] as String? ?? '', precision: 5);

    final maneuvers = <RouteManeuver>[];
    final legs = (route['legs'] as List<dynamic>?) ?? const [];
    for (final legRaw in legs) {
      final steps = ((legRaw as Map<String, dynamic>)['steps'] as List<dynamic>?) ?? const [];
      for (final stepRaw in steps) {
        final step = stepRaw as Map<String, dynamic>;
        final maneuver = step['maneuver'] as Map<String, dynamic>? ?? const {};
        final loc = (maneuver['location'] as List<dynamic>?) ?? const [0, 0];
        maneuvers.add(
          RouteManeuver(
            type: _osrmManeuverType(
              maneuver['type'] as String? ?? 'continue',
              maneuver['modifier'] as String?,
            ),
            instruction: _osrmInstruction(step),
            point: GeoPoint((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
            distanceMeters: (step['distance'] as num?)?.toDouble() ?? 0,
            streetName: step['name'] as String?,
          ),
        );
      }
    }

    return RouteResult(
      profile: profile,
      source: RouteSource.osrm,
      path: path,
      maneuvers: maneuvers,
      distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0,
      durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0,
    );
  }

  RouteResult _straightLineRoute(List<GeoPoint> stops, TravelProfile profile) {
    double distance = 0;
    for (var i = 0; i < stops.length - 1; i++) {
      distance += GeoMath.distanceMeters(stops[i], stops[i + 1]);
    }
    // Rough speed assumptions purely for an offline ETA estimate.
    final speedMps = switch (profile) {
      TravelProfile.drive => 15.0, // ~34 mph
      TravelProfile.bike => 4.5, // ~10 mph
      TravelProfile.walk => 1.3, // ~3 mph
    };

    final maneuvers = <RouteManeuver>[
      RouteManeuver(
        type: ManeuverType.depart,
        instruction: 'Head toward destination',
        point: stops.first,
        distanceMeters: distance,
      ),
      RouteManeuver(
        type: ManeuverType.arrive,
        instruction: 'Arrive at destination',
        point: stops.last,
        distanceMeters: 0,
      ),
    ];

    return RouteResult(
      profile: profile,
      source: RouteSource.straightLine,
      path: stops,
      maneuvers: maneuvers,
      distanceMeters: distance,
      durationSeconds: distance / speedMps,
    );
  }

  static ManeuverType _valhallaManeuverType(int type) {
    switch (type) {
      case 1:
      case 2:
      case 3:
        return ManeuverType.depart;
      case 4:
      case 5:
      case 6:
        return ManeuverType.arrive;
      case 8:
      case 22:
        return ManeuverType.straight;
      case 9:
        return ManeuverType.turnSlightRight;
      case 10:
      case 18:
      case 20:
      case 23:
        return ManeuverType.turnRight;
      case 11:
        return ManeuverType.turnSharpRight;
      case 12:
        return ManeuverType.uturn;
      case 13:
        return ManeuverType.uturn;
      case 14:
        return ManeuverType.turnSharpLeft;
      case 15:
      case 19:
      case 21:
      case 24:
        return ManeuverType.turnLeft;
      case 16:
        return ManeuverType.turnSlightLeft;
      case 17:
        return ManeuverType.straight;
      case 25:
      case 37:
      case 38:
        return ManeuverType.merge;
      case 26:
      case 27:
        return ManeuverType.roundabout;
      default:
        return ManeuverType.straight;
    }
  }

  static ManeuverType _osrmManeuverType(String type, String? modifier) {
    switch (type) {
      case 'depart':
        return ManeuverType.depart;
      case 'arrive':
        return ManeuverType.arrive;
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn':
      case 'exit roundabout':
      case 'exit rotary':
        return ManeuverType.roundabout;
      case 'merge':
      case 'on ramp':
      case 'off ramp':
        return ManeuverType.merge;
      case 'fork':
        return ManeuverType.fork;
      default:
        return _osrmModifierToType(modifier);
    }
  }

  static ManeuverType _osrmModifierToType(String? modifier) {
    switch (modifier) {
      case 'uturn':
        return ManeuverType.uturn;
      case 'sharp right':
        return ManeuverType.turnSharpRight;
      case 'right':
        return ManeuverType.turnRight;
      case 'slight right':
        return ManeuverType.turnSlightRight;
      case 'slight left':
        return ManeuverType.turnSlightLeft;
      case 'left':
        return ManeuverType.turnLeft;
      case 'sharp left':
        return ManeuverType.turnSharpLeft;
      default:
        return ManeuverType.straight;
    }
  }

  static String _osrmInstruction(Map<String, dynamic> step) {
    final maneuver = step['maneuver'] as Map<String, dynamic>? ?? const {};
    final type = maneuver['type'] as String? ?? 'continue';
    final modifier = maneuver['modifier'] as String?;
    final name = step['name'] as String?;
    final street = (name != null && name.isNotEmpty) ? ' onto $name' : '';

    switch (type) {
      case 'depart':
        return 'Head out${street.isEmpty ? '' : street.replaceFirst('onto', 'on')}';
      case 'arrive':
        return 'Arrive at destination';
      default:
        final verb = switch (modifier) {
          'uturn' => 'Make a U-turn',
          'sharp right' => 'Sharp right$street',
          'right' => 'Turn right$street',
          'slight right' => 'Slight right$street',
          'slight left' => 'Slight left$street',
          'left' => 'Turn left$street',
          'sharp left' => 'Sharp left$street',
          _ => 'Continue$street',
        };
        return verb;
    }
  }
}
