import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/endpoints.dart';
import '../models/geo_point.dart';

/// Open-Meteo elevation lookup, batched — used to build elevation profiles
/// for planned routes, the custom route builder, and recorded tracks when
/// the device's own barometric/GPS altitude isn't available or reliable.
class ElevationService {
  ElevationService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static const int _maxPointsPerRequest = 100;

  /// Returns elevation (meters) for each input point, sampled down to at
  /// most ~100 evenly spaced points per request to stay within the public
  /// API's fair-use limits on long routes.
  Future<List<double>> elevationsFor(List<GeoPoint> points) async {
    if (points.isEmpty) return [];
    final results = <double>[];
    for (var offset = 0; offset < points.length; offset += _maxPointsPerRequest) {
      final chunk = points.sublist(
        offset,
        (offset + _maxPointsPerRequest).clamp(0, points.length),
      );
      final lats = chunk.map((p) => p.latitude).join(',');
      final lngs = chunk.map((p) => p.longitude).join(',');
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.openMeteoElevationUrl,
          queryParameters: {'latitude': lats, 'longitude': lngs},
        );
        final elevations = (response.data?['elevation'] as List<dynamic>?) ?? const [];
        results.addAll(elevations.map((e) => (e as num).toDouble()));
      } catch (_) {
        results.addAll(List.filled(chunk.length, 0));
      }
    }
    return results;
  }

  /// Convenience: build an elevation profile (with cumulative distance) by
  /// sampling [path] down to [maxSamples] points, fetching elevations, and
  /// computing total gain/loss with a small noise threshold so GPS/DEM
  /// jitter doesn't inflate the numbers.
  Future<({List<ElevationPoint> profile, double gainMeters, double lossMeters})> profileFor(
    List<GeoPoint> path, {
    int maxSamples = 80,
    double noiseThresholdMeters = 2,
  }) async {
    if (path.length < 2) {
      return (profile: <ElevationPoint>[], gainMeters: 0.0, lossMeters: 0.0);
    }

    final sampleCount = path.length <= maxSamples ? path.length : maxSamples;
    final sampled = <GeoPoint>[];
    final distances = <double>[];
    double cumulative = 0;
    for (var i = 0; i < path.length; i++) {
      if (i > 0) cumulative += GeoMath.distanceMeters(path[i - 1], path[i]);
      final shouldTake = sampleCount >= path.length ||
          (i * (sampleCount - 1)) ~/ (path.length - 1) !=
              ((i - 1).clamp(0, path.length - 1) * (sampleCount - 1)) ~/ (path.length - 1);
      if (i == 0 || i == path.length - 1 || shouldTake) {
        sampled.add(path[i]);
        distances.add(cumulative);
      }
    }

    final elevations = await elevationsFor(sampled);
    double gain = 0;
    double loss = 0;
    for (var i = 1; i < elevations.length; i++) {
      final delta = elevations[i] - elevations[i - 1];
      if (delta.abs() < noiseThresholdMeters) continue;
      if (delta > 0) {
        gain += delta;
      } else {
        loss += -delta;
      }
    }

    final profile = <ElevationPoint>[
      for (var i = 0; i < sampled.length && i < elevations.length; i++)
        ElevationPoint(sampled[i], elevations[i], distanceFromStartMeters: distances[i]),
    ];

    return (profile: profile, gainMeters: gain, lossMeters: loss);
  }
}
