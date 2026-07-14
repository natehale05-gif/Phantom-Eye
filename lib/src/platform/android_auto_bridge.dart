import 'dart:io';

import 'package:flutter/services.dart';

import '../models/route_result.dart';
import '../services/nav_engine.dart';

/// Dart-side half of the Android Auto bridge — mirrors
/// `android/app/src/main/kotlin/.../carapp/NavBridge.kt`. Every
/// [NavProgress] tick from [NavigationSessionNotifier] gets forwarded here;
/// the Kotlin `CarAppService` renders it on the car screen. No-op on
/// iOS/other platforms (CarPlay uses a separate native bridge, see
/// `ios/Runner/CarPlay/`).
class AndroidAutoBridge {
  AndroidAutoBridge._();

  static const _channel = MethodChannel('com.phantomeye.phantom_eye/android_auto');

  // This app only ships for iOS/Android (see `flutter create --platforms`
  // in the project setup), so a direct `Platform.isAndroid` check is safe
  // without an extra web guard.
  static bool get _isSupported => Platform.isAndroid;

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
        'etaEpochMillis': progress.eta.millisecondsSinceEpoch,
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
      // Best-effort — Android Auto not being connected is the common case.
    } on MissingPluginException {
      // Method channel not registered (e.g. running tests) — ignore.
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
