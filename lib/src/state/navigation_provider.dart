import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';
import '../models/route_result.dart';
import '../platform/android_auto_bridge.dart';
import '../platform/carplay_bridge.dart';
import '../services/nav_engine.dart';

/// The single active turn-by-turn session: wraps [NavEngine], subscribes to
/// either live GPS or the demo simulator, and republishes [NavProgress]
/// ticks for every consumer — instruction banner, lane guidance, ETA panel,
/// chase-camera map widget, and (eventually) the CarPlay/Android Auto
/// bridges all watch this same provider.
class ActiveNavigationState {
  const ActiveNavigationState({required this.route, this.progress, this.isSimulated = false});

  final RouteResult route;
  final NavProgress? progress;
  final bool isSimulated;

  ActiveNavigationState copyWith({NavProgress? progress}) =>
      ActiveNavigationState(route: route, progress: progress ?? this.progress, isSimulated: isSimulated);
}

class NavigationSessionNotifier extends Notifier<ActiveNavigationState?> {
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<NavProgress>? _simSub;
  NavEngine? _engine;

  @override
  ActiveNavigationState? build() {
    ref.onDispose(_cancelSubscriptions);
    return null;
  }

  void start(RouteResult route, {bool simulate = false}) {
    _cancelSubscriptions();
    _engine = NavEngine(route);
    state = ActiveNavigationState(route: route, isSimulated: simulate);

    if (simulate) {
      final speed = switch (route.profile) {
        TravelProfile.drive => 13.0,
        TravelProfile.bike => 5.0,
        TravelProfile.walk => 1.4,
      };
      _simSub = _engine!.simulate(speedMps: speed).listen((progress) {
        state = state?.copyWith(progress: progress);
        AndroidAutoBridge.updateProgress(route: route, progress: progress);
        CarPlayBridge.updateProgress(route: route, progress: progress);
        if (progress.hasArrived) stop();
      });
    } else {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 2),
      ).listen((position) {
        final progress = _engine!.computeProgress(
          GeoPoint(position.latitude, position.longitude),
          headingDeg: position.heading >= 0 ? position.heading : null,
          speedMps: position.speed >= 0 ? position.speed : null,
        );
        state = state?.copyWith(progress: progress);
        AndroidAutoBridge.updateProgress(route: route, progress: progress);
        CarPlayBridge.updateProgress(route: route, progress: progress);
        if (progress.hasArrived) stop();
      });
    }
  }

  void stop() {
    _cancelSubscriptions();
    state = null;
    AndroidAutoBridge.stop();
    CarPlayBridge.stop();
  }

  void _cancelSubscriptions() {
    _gpsSub?.cancel();
    _simSub?.cancel();
    _gpsSub = null;
    _simSub = null;
  }
}

final navigationSessionProvider =
    NotifierProvider<NavigationSessionNotifier, ActiveNavigationState?>(NavigationSessionNotifier.new);
