import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/geo_point.dart';
import '../models/place.dart';

class GeocodingService {
  GeocodingService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  /// Forward geocoding / free-text POI search via Photon.
  /// [bias] centers results near the current map viewport, which matters a
  /// lot for a nav app — "Main Street" should resolve near you, not in a
  /// city on the other side of the country.
  Future<List<Place>> search(String query, {GeoPoint? bias, int limit = 12}) async {
    if (query.trim().isEmpty) return [];
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.photonBaseUrl,
      queryParameters: {
        'q': query,
        'limit': limit,
        if (bias != null) 'lat': bias.latitude,
        if (bias != null) 'lon': bias.longitude,
        if (bias != null) 'location_bias_scale': 0.4,
      },
    );
    final features = (response.data?['features'] as List<dynamic>?) ?? const [];
    return features
        .cast<Map<String, dynamic>>()
        .map(Place.fromPhotonFeature)
        .toList(growable: false);
  }

  /// Reverse geocoding — used for "what's under the map center" / long-press
  /// place card fallback when no POI is directly tapped.
  Future<Place?> reverse(GeoPoint point) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${ApiEndpoints.photonBaseUrl}/reverse',
      queryParameters: {'lat': point.latitude, 'lon': point.longitude},
    );
    final features = (response.data?['features'] as List<dynamic>?) ?? const [];
    if (features.isEmpty) return null;
    return Place.fromPhotonFeature(features.first as Map<String, dynamic>);
  }
}
