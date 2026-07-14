import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';

enum LocationPermissionState { unknown, granted, denied, deniedForever, serviceDisabled }

final locationPermissionProvider = FutureProvider<LocationPermissionState>((ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return LocationPermissionState.serviceDisabled;

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  switch (permission) {
    case LocationPermission.denied:
      return LocationPermissionState.denied;
    case LocationPermission.deniedForever:
      return LocationPermissionState.deniedForever;
    case LocationPermission.whileInUse:
    case LocationPermission.always:
      return LocationPermissionState.granted;
    default:
      return LocationPermissionState.unknown;
  }
});

/// Live device position stream, throttled to reasonable distance/interval
/// defaults for a navigation app (battery matters a lot on multi-hour
/// backcountry drives).
final positionStreamProvider = StreamProvider<Position>((ref) {
  const settings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2);
  return Geolocator.getPositionStream(locationSettings: settings);
});

final currentGeoPointProvider = Provider<GeoPoint?>((ref) {
  final position = ref.watch(positionStreamProvider).value;
  if (position == null) return null;
  return GeoPoint(position.latitude, position.longitude);
});
