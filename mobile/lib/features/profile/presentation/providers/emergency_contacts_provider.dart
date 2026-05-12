import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../domain/emergency_contact.dart';

const String _kEmergencyContactsKey = 'emergency_contacts';

final StateNotifierProvider<EmergencyContactsNotifier, List<EmergencyContact>>
    emergencyContactsProvider =
    StateNotifierProvider<EmergencyContactsNotifier, List<EmergencyContact>>(
  (Ref ref) => EmergencyContactsNotifier(ref.read(secureStorageProvider)),
);

class EmergencyContactsNotifier
    extends StateNotifier<List<EmergencyContact>> {
  EmergencyContactsNotifier(this._storage)
      : super(const <EmergencyContact>[]) {
    unawaited(_load());
  }

  final SecureStorage _storage;
  final Uuid _uuid = const Uuid();

  Future<void> _load() async {
    final String? raw = await _storage.readString(_kEmergencyContactsKey);
    if (raw == null || raw.isEmpty) {
      state = const <EmergencyContact>[];
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .whereType<Map<String, dynamic>>()
          .map(EmergencyContact.fromJson)
          .toList();
    } catch (_) {
      state = const <EmergencyContact>[];
    }
  }

  Future<void> _persist() async {
    final String raw =
        jsonEncode(state.map((EmergencyContact c) => c.toJson()).toList());
    await _storage.writeString(_kEmergencyContactsKey, raw);
  }

  Future<EmergencyContact> add({
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final EmergencyContact contact = EmergencyContact(
      id: _uuid.v4(),
      name: name.trim(),
      phone: phone.trim(),
      relationship:
          (relationship == null || relationship.trim().isEmpty)
              ? null
              : relationship.trim(),
    );
    state = <EmergencyContact>[...state, contact];
    await _persist();
    return contact;
  }

  Future<void> update(EmergencyContact updated) async {
    state = state
        .map((EmergencyContact c) => c.id == updated.id ? updated : c)
        .toList();
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((EmergencyContact c) => c.id != id).toList();
    await _persist();
  }
}

