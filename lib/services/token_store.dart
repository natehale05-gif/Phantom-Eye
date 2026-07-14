import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's Cesium ion access token securely on-device.
///
/// A build-time token may also be supplied with
/// `--dart-define=CESIUM_ION_TOKEN=...`; a stored token always takes priority
/// so the user can change keys without rebuilding.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'cesium_ion_token';
  static const _envToken = String.fromEnvironment('CESIUM_ION_TOKEN');

  Future<String?> read() async {
    final stored = (await _storage.read(key: _key))?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final env = _envToken.trim();
    return env.isEmpty ? null : env;
  }

  Future<bool> hasToken() async => (await read()) != null;

  Future<void> save(String token) async {
    await _storage.write(key: _key, value: token.trim());
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
