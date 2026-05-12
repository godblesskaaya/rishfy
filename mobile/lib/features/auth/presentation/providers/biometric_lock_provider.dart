import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/storage/secure_storage.dart';

const String _kBiometricEnabledKey = 'biometric_enabled';

/// Tracks whether the user has enabled biometric app lock, and whether the
/// session is currently "locked" (needs a biometric prompt before showing
/// content).
class BiometricLockState {
  const BiometricLockState({
    required this.enabled,
    required this.locked,
    required this.available,
  });

  /// User has biometric lock enabled in settings.
  final bool enabled;

  /// The app is currently locked (user must re-authenticate before continuing).
  final bool locked;

  /// Device supports biometric auth (fingerprint, face).
  final bool available;

  BiometricLockState copyWith({
    bool? enabled,
    bool? locked,
    bool? available,
  }) =>
      BiometricLockState(
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        available: available ?? this.available,
      );
}

final StateNotifierProvider<BiometricLockNotifier, BiometricLockState>
    biometricLockProvider =
    StateNotifierProvider<BiometricLockNotifier, BiometricLockState>(
  (Ref ref) => BiometricLockNotifier(ref.read(secureStorageProvider)),
);

class BiometricLockNotifier extends StateNotifier<BiometricLockState> {
  BiometricLockNotifier(this._storage)
      : super(const BiometricLockState(
          enabled: false,
          locked: false,
          available: false,
        )) {
    unawaited(_init());
  }

  final SecureStorage _storage;
  final LocalAuthentication _auth = LocalAuthentication();

  Future<void> _init() async {
    final bool available = await _checkAvailability();
    final String? raw = await _storage.readString(_kBiometricEnabledKey);
    final bool enabled = raw == 'true';
    state = BiometricLockState(
      enabled: enabled,
      // If lock is enabled, app starts locked on cold boot.
      locked: enabled && available,
      available: available,
    );
  }

  Future<bool> _checkAvailability() async {
    try {
      final bool supported = await _auth.isDeviceSupported();
      final bool canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  /// Enable lock. Verifies biometrics before persisting so users aren't
  /// locked out by accident.
  Future<bool> enable() async {
    if (!state.available) return false;
    final bool ok = await _authenticate('Confirm to enable app lock');
    if (!ok) return false;
    await _storage.writeString(_kBiometricEnabledKey, 'true');
    state = state.copyWith(enabled: true, locked: false);
    return true;
  }

  Future<bool> disable() async {
    final bool ok = await _authenticate('Confirm to disable app lock');
    if (!ok) return false;
    await _storage.writeString(_kBiometricEnabledKey, 'false');
    state = state.copyWith(enabled: false, locked: false);
    return true;
  }

  /// Lock now (e.g. on app resume from background).
  void lock() {
    if (!state.enabled) return;
    state = state.copyWith(locked: true);
  }

  /// Prompt for biometric auth and unlock on success.
  Future<bool> unlock() async {
    if (!state.locked) return true;
    final bool ok = await _authenticate('Unlock Rishfy');
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  Future<bool> _authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
