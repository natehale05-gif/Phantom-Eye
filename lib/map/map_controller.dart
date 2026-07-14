import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/place.dart';

/// A single geocoding search hit returned by the web map.
class SearchResult {
  const SearchResult({
    required this.displayName,
    required this.lon,
    required this.lat,
    required this.height,
  });

  final String displayName;
  final double lon;
  final double lat;
  final double height;

  static SearchResult fromJson(Map<dynamic, dynamic> json) => SearchResult(
        displayName: json['displayName'] as String? ?? 'Unknown',
        lon: (json['lon'] as num?)?.toDouble() ?? 0,
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        height: (json['height'] as num?)?.toDouble() ?? 2000,
      );
}

enum MapErrorKind { token, network, other }

/// Drives the embedded CesiumJS surface and translates its bridge events into
/// Flutter-friendly notifiers and streams.
class MapController {
  InAppWebViewController? _web;

  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<bool> loading = ValueNotifier(false);
  final ValueNotifier<String> loadingLabel = ValueNotifier('Loading');
  final ValueNotifier<String> mode = ValueNotifier('photoreal');

  final _errors = StreamController<({MapErrorKind kind, String message})>.broadcast();
  final _searchResults = StreamController<List<SearchResult>>.broadcast();

  Stream<({MapErrorKind kind, String message})> get errors => _errors.stream;
  Stream<List<SearchResult>> get searchResults => _searchResults.stream;

  String? _pendingToken;

  /// Called from the WebView's `onWebViewCreated`.
  void attach(InAppWebViewController controller) {
    _web = controller;
    controller.addJavaScriptHandler(
      handlerName: 'phantomEye',
      callback: (args) => _onBridgeEvent(args),
    );
  }

  void _onBridgeEvent(List<dynamic> args) {
    if (args.isEmpty) return;
    final event = args[0] as String;
    final data = args.length > 1 && args[1] is Map
        ? args[1] as Map<dynamic, dynamic>
        : const {};

    switch (event) {
      case 'pageReady':
        // The page is up; push any token that was queued before load finished.
        if (_pendingToken != null) {
          setToken(_pendingToken!);
          _pendingToken = null;
        }
        break;
      case 'ready':
        ready.value = true;
        break;
      case 'loading':
        loading.value = data['on'] == true;
        if (data['label'] is String) loadingLabel.value = data['label'] as String;
        break;
      case 'modeChanged':
        if (data['mode'] is String) mode.value = data['mode'] as String;
        break;
      case 'searchResults':
        final items = (data['items'] as List? ?? [])
            .whereType<Map>()
            .map(SearchResult.fromJson)
            .toList();
        _searchResults.add(items);
        break;
      case 'error':
        _errors.add((
          kind: _kind(data['kind'] as String?),
          message: data['message'] as String? ?? 'Unknown error',
        ));
        break;
    }
  }

  MapErrorKind _kind(String? kind) => switch (kind) {
        'token' => MapErrorKind.token,
        'network' => MapErrorKind.network,
        _ => MapErrorKind.other,
      };

  Future<void> _eval(String js) async {
    final web = _web;
    if (web == null) return;
    await web.evaluateJavascript(source: js);
  }

  /// Provides the ion token to the map. If the page hasn't finished loading
  /// yet, the token is queued and sent on `pageReady`.
  void setToken(String token) {
    final escaped = _escape(token);
    if (_web == null) {
      _pendingToken = token;
      return;
    }
    _eval("window.PE && window.PE.setToken('$escaped');");
  }

  void queueToken(String token) => _pendingToken = token;

  void flyToPlace(Place p) {
    _eval(
      'window.PE && window.PE.flyTo(${p.lon}, ${p.lat}, ${p.height}, '
      '${p.heading}, ${p.pitch}, 3.4);',
    );
  }

  void flyToResult(int index) {
    _eval('window.PE && window.PE.flyToSearchResult($index);');
  }

  void flyHome() => _eval('window.PE && window.PE.flyHome(2.6);');

  void setMode(String m) {
    mode.value = m;
    _eval("window.PE && window.PE.setMode('$m');");
  }

  void search(String query) {
    _eval("window.PE && window.PE.search('${_escape(query)}');");
  }

  String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', ' ');

  void dispose() {
    _errors.close();
    _searchResults.close();
    ready.dispose();
    loading.dispose();
    loadingLabel.dispose();
    mode.dispose();
  }
}
