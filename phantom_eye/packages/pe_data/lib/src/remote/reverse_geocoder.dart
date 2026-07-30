import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pe_core/pe_core.dart';

import 'photon_client.dart';

/// BigDataCloud's keyless reverse-geocode endpoint, used as the fallback.
const String kBigDataCloudUrl =
    'https://api.bigdatacloud.net/data/reverse-geocode-client';

/// What the UI shows when no provider could name the point.
///
/// Ported from `src/weather.ts:294`. Reverse geocoding backs a display label
/// only, so a failure must degrade to this rather than fail the weather load.
const String kUnknownPlaceName = 'Current Location';

/// Pick a settlement name out of a BigDataCloud response.
///
/// Ported from `src/weather.ts:292`. `locality` comes **before** `city`
/// deliberately: BigDataCloud's `city` snaps to a broader administrative
/// area — it reports "Albany" for Corvallis — so the granular field wins.
String? parseBigDataCloudName(Map<String, dynamic> body) =>
    _str(body['locality']) ??
    _str(body['city']) ??
    _str(body['principalSubdivision']) ??
    _str(body['countryName']);

/// Resolves a friendly place name for a coordinate.
///
/// Ported from `reverseName` in `src/weather.ts:255`. The chain is Photon,
/// then BigDataCloud, then the [kUnknownPlaceName] literal. Photon leads
/// because it returns the actual town rather than the administrative city it
/// sits inside.
///
/// The two providers are tried **in sequence, not raced** — unlike the
/// Overpass mirrors, these are not interchangeable. Photon's answer is the
/// better one, so a fast BigDataCloud reply must not be allowed to win.
final class ReverseGeocoder {
  ReverseGeocoder({
    http.Client? client,
    PhotonClient? photon,
    this.bigDataCloudUrl = kBigDataCloudUrl,
  }) : _client = client ?? http.Client(),
       _photon = photon ?? PhotonClient(client: client);

  final http.Client _client;
  final PhotonClient _photon;
  final String bigDataCloudUrl;

  /// Never throws; falls back to [kUnknownPlaceName].
  Future<String> nameFor(LngLat at) async {
    final fromPhoton = await _photon.reverseName(at);
    if (fromPhoton != null && fromPhoton.isNotEmpty) return fromPhoton;
    return await _bigDataCloud(at) ?? kUnknownPlaceName;
  }

  Future<String?> _bigDataCloud(LngLat at) async {
    try {
      final uri = Uri.parse(bigDataCloudUrl).replace(
        queryParameters: {
          'latitude': '${at.lat}',
          'longitude': '${at.lon}',
          'localityLanguage': 'en',
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map<String, dynamic>) return null;
      return parseBigDataCloudName(decoded);
    } on Object {
      return null;
    }
  }

  void close() {
    _photon.close();
    _client.close();
  }
}

String? _str(Object? v) => (v is String && v.isNotEmpty) ? v : null;
