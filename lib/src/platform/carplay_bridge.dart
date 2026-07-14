import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/route_result.dart';
import '../services/nav_engine.dart';

/// Dart-side half of the CarPlay bridge — mirrors
/// `ios/Runner/CarPlay/NavBridge.swift`. See that file (and
/// `ios/Runner/CarPlay/README.md`) for the CarPlay navigation entitlement
/// this requires and the fact that the native side is an unverified draft
/// (written without Xcode available to compile it).
///
/// Uses [defaultTargetPlatform] rather than `dart:io`'s `Platform` so this
/// file doesn't break the web build (see `AndroidAutoBridge` for the same
/// reasoning).
class CarPlayBridge {
  CarPlayBridge._();

  static const _channel = MethodChannel('com.phantomeye.phantom_eye/carplay');

  static bool get _isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> updateProgress({
    required RouteResult route,
    required NavProgress progress,
  }) async {
    if (!_isSupported) return;
    final maneuvers = route.maneuvers;
    final maneuver = maneuvers.isEmpty
        ? null
        : maneuvers[progress.currentManeuverIndex.clamp(0, maneuvers.length - 1)];

    try {
      await _channel.invokeMethod<void>('updateNavState', {
        'isNavigating': true,
        'puckLat': progress.puckPoint.latitude,
        'puckLng': progress.puckPoint.longitude,
        'puckBearingDeg': progress.puckBearingDeg,
        'route': route.path.map((p) => [p.latitude, p.longitude]).toList(),
        'distanceRemainingMeters': progress.distanceRemainingMeters,
        'durationRemainingSeconds': progress.durationRemainingSeconds,
        'etaEpochMillis': progress.eta.millisecondsSinceEpoch.toDouble(),
        'maneuver': maneuver == null
            ? null
            : {
                'instruction': maneuver.instruction,
                'distanceMeters': progress.distanceToManeuverMeters,
                'streetName': maneuver.streetName,
              },
        'hasArrived': progress.hasArrived,
      });
    } on PlatformException {
      // Best-effort — CarPlay not being connected is the common case.
    } on MissingPluginException {
      // Ignore (e.g. running tests, or native side not yet wired in Xcode).
    }
  }

  static Future<void> stop() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('stopNavigation');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }
}
