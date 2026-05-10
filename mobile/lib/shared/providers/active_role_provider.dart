import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/secure_storage.dart';

final StateNotifierProvider<ActiveRoleNotifier, String> activeRoleProvider =
    StateNotifierProvider<ActiveRoleNotifier, String>(
  (Ref ref) => ActiveRoleNotifier(ref.read(secureStorageProvider)),
);

class ActiveRoleNotifier extends StateNotifier<String> {
  ActiveRoleNotifier(this._storage) : super('passenger') {
    unawaited(_load());
  }

  final SecureStorage _storage;

  Future<void> _load() async {
    final String? cachedRole = await _storage.readActiveRole();
    if (cachedRole == 'driver' || cachedRole == 'passenger') {
      state = cachedRole!;
    }
  }

  Future<void> setRole(String role) async {
    state = role;
    await _storage.writeActiveRole(role);
  }
}
