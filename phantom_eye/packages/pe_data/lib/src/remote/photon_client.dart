import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pe_core/pe_core.dart';

import '../parse/photon_parser.dart';

/// Photon search and reverse-geocode endpoints.
///
/// Ported from `src/geocode.ts` and `reverseName` in `src/weather.ts`.
const String kPhotonSearchUrl = 'https://photon.komoot.io/api/';
const String kPhotonReverseUrl = 'https://photon.komoot.io/reverse';

/// Maximum forward-search results requested.
///
/// Ported from `limit: '7'` in `src/geocode.ts:55`.
const int kPhotonSearchLimit = 7;

/// Queries shorter than this are not sent at all.
///
/// Ported from `if (q.length < 2) return []` in `src/geocode.ts:53`. A
/// one-character query matches half of OSM and is never what the user meant.
const int kMinSearchQueryLength = 2;

/// Thrown when a search request fails outright.
///
/// The original threw `Search failed (<status>)` so the UI could show the
/// status; [statusCode] is null for transport errors, which never reached
/// that path in the browser because `fetch` rejected instead.
final class SearchException implements Exception {
  const SearchException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'SearchException: $message';
}

/// Text place search and reverse geocoding via Photon.
final class PhotonClient {
  PhotonClient({
    http.Client? client,
    this.searchUrl = kPhotonSearchUrl,
    this.reverseUrl = kPhotonReverseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String searchUrl;
  final String reverseUrl;

  /// Forward search, optionally biased toward [near].
  ///
  /// Returns an empty list — not an error — for a too-short query, matching
  /// the original, because this runs on every keystroke.
  ///
  /// Throws [SearchException] when the request fails, which the caller
  /// surfaces to the user: unlike Overpass there is no second mirror to fall
  /// back to, so a failure here really is a failed search.
  Future<List<Place>> search(String query, {LngLat? near}) async {
    final q = query.trim();
    if (q.length < kMinSearchQueryLength) return const [];

    final uri = Uri.parse(searchUrl).replace(
      queryParameters: <String, String>{
        'q': q,
        'limit': '$kPhotonSearchLimit',
        'lang': 'en',
        if (near != null) 'lat': '${near.lat}',
        if (near != null) 'lon': '${near.lon}',
      },
    );

    final http.Response response;
    try {
      response = await _client.get(uri);
    } on http.ClientException catch (e) {
      throw SearchException(e.message);
    }
    if (response.statusCode != 200) {
      throw SearchException(
        'Search failed (${response.statusCode})',
        response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(_body(response));
    } on FormatException catch (e) {
      // A 200 carrying an HTML error page. Surfaced as a search failure so
      // the caller sees one exception type, never a raw FormatException.
      throw SearchException('Search returned invalid data (${e.message})');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SearchException('Search returned an unexpected response');
    }
    return parsePhotonSearch(decoded);
  }

  /// Reverse-geocode a friendly settlement name, or null if none is found.
  ///
  /// Never throws: this feeds a display label, and a missing name must fall
  /// through to the next provider rather than fail the whole weather load.
  Future<String?> reverseName(LngLat at) async {
    try {
      final uri = Uri.parse(
        reverseUrl,
      ).replace(queryParameters: {'lon': '${at.lon}', 'lat': '${at.lat}'});
      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(_body(response));
      if (decoded is! Map<String, dynamic>) return null;
      return parsePhotonReverseName(decoded);
    } on Object {
      // Transport error, malformed JSON — all mean "no name from Photon".
      return null;
    }
  }

  void close() => _client.close();
}

/// Decode the body as UTF-8.
///
/// `http.Response.body` follows the `Content-Type` charset, which Photon
/// sometimes omits — that would decode place names as Latin-1 and turn
/// `Köln` into `KÃ¶ln`. Photon is always UTF-8, so decode it as such.
///
/// `allowMalformed` keeps a truncated body from throwing a `FormatException`
/// out of the decoder; the JSON parse that follows will reject it properly as
/// a search failure instead.
String _body(http.Response response) =>
    utf8.decode(response.bodyBytes, allowMalformed: true);
