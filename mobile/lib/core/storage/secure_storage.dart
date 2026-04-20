import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

/// Provider exposing the [SecureStorage] singleton.
final Provider<SecureStorage> secureStorageProvider = Provider<SecureStorage>(
  (Ref ref) => SecureStorage(),
);

/// Wraps [FlutterSecureStorage] with semantic methods.
///
/// On Android: AES encryption with keys in Keystore.
/// On iOS: Keychain with default (first_unlock_this_device) accessibility.
class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  // ------------------------------ Tokens ------------------------------------

  Future<void> writeAccessToken(String token) =>
      _storage.write(key: AppConstants.keyAccessToken, value: token);

  Future<String?> readAccessToken() =>
      _storage.read(key: AppConstants.keyAccessToken);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: AppConstants.keyRefreshToken, value: token);

  Future<String?> readRefreshToken() =>
      _storage.read(key: AppConstants.keyRefreshToken);

  Future<void> clearTokens() async {
    await _storage.delete(key: AppConstants.keyAccessToken);
    await _storage.delete(key: AppConstants.keyRefreshToken);
  }

  // ------------------------------ Session -----------------------------------

  Future<void> writeUserId(String userId) =>
      _storage.write(key: AppConstants.keyUserId, value: userId);

  Future<String?> readUserId() =>
      _storage.read(key: AppConstants.keyUserId);

  Future<void> writeDeviceId(String deviceId) =>
      _storage.write(key: AppConstants.keyDeviceId, value: deviceId);

  Future<String?> readDeviceId() =>
      _storage.read(key: AppConstants.keyDeviceId);

  // ------------------------------ Preferences --------------------------------

  Future<void> writeActiveRole(String role) =>
      _storage.write(key: AppConstants.keyActiveRole, value: role);

  Future<String?> readActiveRole() =>
      _storage.read(key: AppConstants.keyActiveRole);

  Future<void> writeBiometricEnabled(bool enabled) => _storage.write(
        key: AppConstants.keyBiometricEnabled,
        value: enabled.toString(),
      );

  Future<bool> readBiometricEnabled() async {
    final String? value = await _storage.read(
      key: AppConstants.keyBiometricEnabled,
    );
    return value == 'true';
  }

  // ------------------------------ Utilities ----------------------------------

  /// Nuke everything — called on logout.
  Future<void> clear() async {
    await _storage.deleteAll();
  }

  Future<bool> containsKey(String key) => _storage.containsKey(key: key);
}
