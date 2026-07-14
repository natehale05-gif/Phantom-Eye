import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'settings_providers.dart';

enum MapBaseStyle { streets, satellite, topo }

extension MapBaseStyleX on MapBaseStyle {
  String get label => switch (this) {
        MapBaseStyle.streets => 'Streets',
        MapBaseStyle.satellite => 'Satellite',
        MapBaseStyle.topo => 'Topo',
      };
}

class MapBaseStyleNotifier extends Notifier<MapBaseStyle> {
  @override
  MapBaseStyle build() {
    // Offroad mode defaults to the topo basemap (contours/trails); everyday
    // mode defaults to the familiar streets basemap.
    return ref.read(appModeProvider) == AppMode.offroad ? MapBaseStyle.topo : MapBaseStyle.streets;
  }

  void set(MapBaseStyle value) => state = value;

  void cycle() {
    const order = [MapBaseStyle.streets, MapBaseStyle.satellite, MapBaseStyle.topo];
    state = order[(order.indexOf(state) + 1) % order.length];
  }
}

final mapBaseStyleProvider = NotifierProvider<MapBaseStyleNotifier, MapBaseStyle>(MapBaseStyleNotifier.new);

class HillshadeOverlayNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
}

final hillshadeOverlayProvider = NotifierProvider<HillshadeOverlayNotifier, bool>(HillshadeOverlayNotifier.new);
