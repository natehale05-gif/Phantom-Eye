import 'package:dio/dio.dart';

/// Thin wrapper around a shared [Dio] instance: sane timeouts + a
/// descriptive User-Agent (Nominatim/Photon/OSM tile policies all ask
/// clients to identify themselves) applied to every outbound request.
class ApiClient {
  ApiClient._(this.dio);

  final Dio dio;

  static final ApiClient instance = ApiClient._(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'User-Agent': 'PhantomEye/1.0 (+https://phantomeye.app)'},
      ),
    ),
  );
}
