import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Very small typed wrapper around [SharedPreferences] for simple
/// persisted settings (units toggle, theme, recents, onboarding-seen flag).
/// Structured data (tracks, saved routes, waypoints) lives in
/// [FileStore] instead — SharedPreferences is not meant for growing lists
/// of GPS points.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStore(prefs);
  }

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  List<String> getStringList(String key) => _prefs.getStringList(key) ?? const [];
  Future<void> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);

  T? getJson<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, dynamic> json) =>
      _prefs.setString(key, jsonEncode(json));

  Future<void> remove(String key) => _prefs.remove(key);
}

abstract final class StoreKeys {
  static const String unitSystem = 'settings.unit_system';
  static const String appMode = 'settings.app_mode';
  static const String themeMode = 'settings.theme_mode';
  static const String onboardingComplete = 'settings.onboarding_complete';
  static const String recentSearches = 'search.recents';
  static const String meshtasticLastDeviceId = 'meshtastic.last_device_id';
}
