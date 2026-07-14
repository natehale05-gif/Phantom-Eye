import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/file_store.dart';
import '../core/storage/local_store.dart';
import '../services/elevation_service.dart';
import '../services/geocoding_service.dart';
import '../services/gpx_service.dart';
import '../services/routing_service.dart';
import '../services/weather_service.dart';

/// Infra singletons. [localStoreProvider]/[fileStoreProvider] are
/// overridden in `main()` once the async setup (SharedPreferences,
/// documents directory) resolves — see [bootstrapProviders].
final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden at app bootstrap');
});

final fileStoreProvider = Provider<FileStore>((ref) {
  throw UnimplementedError('fileStoreProvider must be overridden at app bootstrap');
});

final geocodingServiceProvider = Provider((ref) => GeocodingService());
final weatherServiceProvider = Provider((ref) => WeatherService());
final routingServiceProvider = Provider((ref) => RoutingService());
final elevationServiceProvider = Provider((ref) => ElevationService());
final gpxServiceProvider = Provider((ref) => GpxService());
