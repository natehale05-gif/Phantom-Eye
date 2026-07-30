import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pe_core/pe_core.dart';

/// The Overpass mirrors raced against each other.
///
/// Ported from `ENDPOINTS` in `src/overpass.ts`. Region-limited mirrors are
/// deliberately excluded. Both are launched simultaneously and the first
/// success wins.
const List<String> kOverpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

/// Per-attempt timeout.
///
/// Ported from the default `timeoutMs` in `src/overpass.ts`.
const Duration kOverpassTimeout = Duration(seconds: 25);

/// A decoded Overpass response: just the element list.
final class OverpassResult {
  const OverpassResult(this.elements);
  final List<Map<String, dynamic>> elements;

  bool get isEmpty => elements.isEmpty;
  int get length => elements.length;
}

/// Queries Overpass, racing two mirrors.
///
/// Mirror racing exists because these public mirrors return frequent 504s and
/// sequential fallback was too slow. That makes **fast failure the common
/// case**, which is exactly why this is built on [raceForFirstSuccess] rather
/// than `Future.any` — the latter would let the first mirror to fail kill the
/// whole request. See that function's docs.
///
/// Returns null when *every* mirror failed, matching the original, which never
/// threw. Callers treat null as "no data this time" and retry on the next
/// settle rather than surfacing an error.
final class OverpassClient {
  OverpassClient({
    http.Client? client,
    this.endpoints = kOverpassEndpoints,
    this.timeout = kOverpassTimeout,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final List<String> endpoints;
  final Duration timeout;

  /// Run `query` and decode the `elements` array.
  Future<OverpassResult?> query(String query) async {
    try {
      return await raceForFirstSuccess<OverpassResult>([
        for (final endpoint in endpoints) () => _fetch(endpoint, query),
      ], attemptTimeout: timeout);
    } on AllAttemptsFailedException {
      // Every mirror failed. The legacy contract is a null result, not a throw.
      return null;
    }
  }

  /// Fetch and decode from one mirror.
  ///
  /// Decoding happens **inside** the attempt, deliberately. A mirror that
  /// answers 200 with a truncated or HTML error body should count as *that
  /// mirror* failing, leaving the other free to win — which is what the
  /// original did by awaiting `res.json()` per attempt. Decoding after the
  /// race instead would let a fast garbage response take the win and then
  /// throw, breaking the never-throws contract.
  Future<OverpassResult> _fetch(String endpoint, String query) async {
    final uri = Uri.parse(endpoint);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      // The original sends `data=` followed by the URL-encoded query, rather
      // than letting a form encoder handle the whole body.
      body: 'data=${Uri.encodeQueryComponent(query)}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Counts as this mirror failing, not as a failure of the request — the
      // other mirror may still succeed.
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw http.ClientException('response was not a JSON object', uri);
    }
    final elements = decoded['elements'];
    if (elements is! List) {
      throw http.ClientException('response had no elements array', uri);
    }
    return OverpassResult([
      for (final e in elements)
        if (e is Map<String, dynamic>) e,
    ]);
  }

  void close() => _client.close();
}
