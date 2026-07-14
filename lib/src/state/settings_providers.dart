import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_store.dart';
import '../models/unit_system.dart';
import '../theme/app_theme.dart';
import 'core_providers.dart';

class UnitSystemNotifier extends Notifier<UnitSystem> {
  @override
  UnitSystem build() {
    final saved = ref.read(localStoreProvider).getString(StoreKeys.unitSystem);
    return saved == 'metric' ? UnitSystem.metric : UnitSystem.imperial;
  }

  void set(UnitSystem value) {
    state = value;
    ref.read(localStoreProvider).setString(StoreKeys.unitSystem, value.name);
  }

  void toggle() => set(state == UnitSystem.imperial ? UnitSystem.metric : UnitSystem.imperial);
}

final unitSystemProvider = NotifierProvider<UnitSystemNotifier, UnitSystem>(UnitSystemNotifier.new);

class AppModeNotifier extends Notifier<AppMode> {
  @override
  AppMode build() {
    final saved = ref.read(localStoreProvider).getString(StoreKeys.appMode);
    return saved == 'offroad' ? AppMode.offroad : AppMode.everyday;
  }

  void set(AppMode value) {
    state = value;
    ref.read(localStoreProvider).setString(StoreKeys.appMode, value.name);
  }

  void toggle() => set(state == AppMode.everyday ? AppMode.offroad : AppMode.everyday);
}

final appModeProvider = NotifierProvider<AppModeNotifier, AppMode>(AppModeNotifier.new);

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(localStoreProvider).getBool(StoreKeys.onboardingComplete) ?? false;

  void complete() {
    state = true;
    ref.read(localStoreProvider).setBool(StoreKeys.onboardingComplete, true);
  }
}

final onboardingCompleteProvider = NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);
