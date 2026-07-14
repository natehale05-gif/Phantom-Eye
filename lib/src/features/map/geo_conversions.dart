import 'package:maplibre_gl/maplibre_gl.dart' as mgl;

import '../../models/geo_point.dart';

/// The only place in the app allowed to know about `maplibre_gl`'s LatLng —
/// every other layer (models, services, state) stays map-plugin-agnostic so
/// swapping map engines later only touches `features/map/`.
extension GeoPointToLatLng on GeoPoint {
  mgl.LatLng toLatLng() => mgl.LatLng(latitude, longitude);
}

extension LatLngToGeoPoint on mgl.LatLng {
  GeoPoint toGeoPoint() => GeoPoint(latitude, longitude);
}
