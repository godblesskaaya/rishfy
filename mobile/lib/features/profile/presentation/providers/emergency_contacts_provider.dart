import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/profile_remote_datasource.dart';
import '../../domain/emergency_contact.dart';

final StateNotifierProvider<EmergencyContactsNotifier, List<EmergencyContact>>
    emergencyContactsProvider =
    StateNotifierProvider<EmergencyContactsNotifier, List<EmergencyContact>>(
  (Ref ref) =>
      EmergencyContactsNotifier(ref.read(profileRemoteDataSourceProvider)),
);

class EmergencyContactsNotifier extends StateNotifier<List<EmergencyContact>> {
  EmergencyContactsNotifier(this._dataSource)
      : super(const <EmergencyContact>[]) {
    unawaited(refresh());
  }

  final ProfileRemoteDataSource _dataSource;

  Future<void> refresh() async {
    state = await _dataSource.listEmergencyContacts();
  }

  Future<EmergencyContact> add({
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final EmergencyContact contact = await _dataSource.addEmergencyContact(
      name: name,
      phone: phone,
      relationship: relationship,
    );
    await refresh();
    return contact;
  }

  Future<void> update(EmergencyContact updated) async {
    await _dataSource.updateEmergencyContact(updated);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _dataSource.deleteEmergencyContact(id);
    state = state.where((EmergencyContact c) => c.id != id).toList();
  }
}
