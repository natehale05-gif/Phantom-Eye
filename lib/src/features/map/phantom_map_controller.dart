import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../models/geo_point.dart';
import '../../models/mesh_node.dart';
import '../../models/place.dart';
import '../../models/waypoint.dart';
import '../../theme/app_colors.dart';
import 'color_hex.dart';
import 'geo_conversions.dart';

/// Thin, purpose-built annotation manager over [MapLibreMapController].
///
/// `maplibre_gl`'s annotation API is imperative (add/remove by handle), so
/// every "layer" this app needs (route line, search pins, waypoints, mesh
/// friends, route-builder trail) is modeled here as "diff the whole layer
/// against new data" rather than fine-grained add/remove — simple to reason
/// about and plenty fast at the marker counts this app deals with (tens,
/// not thousands).
class PhantomMapController {
  PhantomMapController(this.controller);

  final MapLibreMapController controller;

  Line? _routeLine;
  List<Circle> _routeWaypointDots = [];
  List<Symbol> _routeWaypointLabels = [];

  List<Circle> _waypointDots = [];
  List<Symbol> _waypointLabels = [];

  List<Circle> _meshDots = [];
  List<Symbol> _meshLabels = [];

  Circle? _placePinDot;
  Symbol? _placePinLabel;

  Future<void> flyTo(GeoPoint point, {double zoom = 15}) async {
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(point.toLatLng(), zoom),
      duration: const Duration(milliseconds: 900),
    );
  }

  Future<void> fitBounds(List<GeoPoint> points, {double padding = 64}) async {
    if (points.isEmpty) return;
    if (points.length == 1) {
      await flyTo(points.first);
      return;
    }
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
      minLng = minLng < p.longitude ? minLng : p.longitude;
      maxLng = maxLng > p.longitude ? maxLng : p.longitude;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        left: padding,
        right: padding,
        top: padding,
        bottom: padding,
      ),
    );
  }

  // --- Route preview line -------------------------------------------------

  Future<void> setRouteLine(List<GeoPoint> path, {Color? color}) async {
    if (_routeLine != null) {
      await controller.removeLine(_routeLine!);
      _routeLine = null;
    }
    if (path.length < 2) return;
    _routeLine = await controller.addLine(
      LineOptions(
        geometry: path.map((p) => p.toLatLng()).toList(),
        lineColor: (color ?? AppColors.accentEveryday).toHex(),
        lineWidth: 5,
        lineOpacity: 0.95,
        lineJoin: 'round',
      ),
    );
  }

  Future<void> clearRouteLine() async {
    if (_routeLine != null) {
      await controller.removeLine(_routeLine!);
      _routeLine = null;
    }
  }

  // --- Custom route builder trail ------------------------------------------

  Future<void> setRouteBuilderWaypoints(List<GeoPoint> points, {Color? color}) async {
    await controller.removeCircles(_routeWaypointDots);
    await controller.removeSymbols(_routeWaypointLabels);
    _routeWaypointDots = [];
    _routeWaypointLabels = [];

    final accent = color ?? AppColors.accentOffroad;
    for (var i = 0; i < points.length; i++) {
      final dot = await controller.addCircle(
        CircleOptions(
          geometry: points[i].toLatLng(),
          circleRadius: 12,
          circleColor: accent.toHex(),
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
      );
      final label = await controller.addSymbol(
        SymbolOptions(
          geometry: points[i].toLatLng(),
          textField: '${i + 1}',
          textColor: '#ffffff',
          textSize: 12,
          textOffset: const Offset(0, 0),
        ),
      );
      _routeWaypointDots.add(dot);
      _routeWaypointLabels.add(label);
    }
  }

  // --- Saved waypoints ------------------------------------------------------

  Future<void> setWaypoints(List<Waypoint> waypoints) async {
    await controller.removeCircles(_waypointDots);
    await controller.removeSymbols(_waypointLabels);
    _waypointDots = [];
    _waypointLabels = [];

    for (final w in waypoints) {
      final dot = await controller.addCircle(
        CircleOptions(
          geometry: w.point.toLatLng(),
          circleRadius: 7,
          circleColor: AppColors.accentOffroad.toHex(),
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
      );
      final label = await controller.addSymbol(
        SymbolOptions(
          geometry: w.point.toLatLng(),
          textField: w.name,
          textColor: '#ffffff',
          textHaloColor: '#00000099',
          textHaloWidth: 1,
          textSize: 12,
          textOffset: const Offset(0, 1.4),
        ),
      );
      _waypointDots.add(dot);
      _waypointLabels.add(label);
    }
  }

  // --- Mesh friends -----------------------------------------------------

  Future<void> setMeshNodes(Iterable<MeshNode> nodes) async {
    await controller.removeCircles(_meshDots);
    await controller.removeSymbols(_meshLabels);
    _meshDots = [];
    _meshLabels = [];

    for (final node in nodes) {
      final point = node.point;
      if (point == null || node.isSelf) continue;
      final color = AppColors.meshColorForNodeNum(node.nodeNum);
      final dot = await controller.addCircle(
        CircleOptions(
          geometry: point.toLatLng(),
          circleRadius: 8,
          circleColor: color.toHex(),
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
      );
      final label = await controller.addSymbol(
        SymbolOptions(
          geometry: point.toLatLng(),
          textField: node.shortName ?? node.displayName,
          textColor: '#ffffff',
          textHaloColor: '#00000099',
          textHaloWidth: 1,
          textSize: 12,
          textOffset: const Offset(0, 1.4),
        ),
      );
      _meshDots.add(dot);
      _meshLabels.add(label);
    }
  }

  // --- Selected place / search result pin --------------------------------

  Future<void> setPlacePin(Place? place) async {
    if (_placePinDot != null) {
      await controller.removeCircle(_placePinDot!);
      _placePinDot = null;
    }
    if (_placePinLabel != null) {
      await controller.removeSymbol(_placePinLabel!);
      _placePinLabel = null;
    }
    if (place == null) return;
    _placePinDot = await controller.addCircle(
      CircleOptions(
        geometry: place.point.toLatLng(),
        circleRadius: 9,
        circleColor: AppColors.accentEveryday.toHex(),
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 3,
      ),
    );
    _placePinLabel = await controller.addSymbol(
      SymbolOptions(
        geometry: place.point.toLatLng(),
        textField: place.name,
        textColor: '#ffffff',
        textHaloColor: '#00000099',
        textHaloWidth: 1,
        textSize: 13,
        textOffset: const Offset(0, 1.5),
      ),
    );
  }

  Future<void> disposeAllAnnotations() async {
    await controller.clearLines();
    await controller.clearCircles();
    await controller.clearSymbols();
  }
}
