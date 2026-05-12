import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/storage/secure_storage.dart';
import '../../domain/payment_method.dart';

const String _kPaymentMethodsKey = 'payment_methods';

final StateNotifierProvider<PaymentMethodsNotifier, List<PaymentMethod>>
    paymentMethodsProvider =
    StateNotifierProvider<PaymentMethodsNotifier, List<PaymentMethod>>(
  (Ref ref) => PaymentMethodsNotifier(ref.read(secureStorageProvider)),
);

class PaymentMethodsNotifier extends StateNotifier<List<PaymentMethod>> {
  PaymentMethodsNotifier(this._storage) : super(const <PaymentMethod>[]) {
    unawaited(_load());
  }

  final SecureStorage _storage;
  final Uuid _uuid = const Uuid();

  Future<void> _load() async {
    final String? raw = await _storage.readString(_kPaymentMethodsKey);
    if (raw == null || raw.isEmpty) {
      state = const <PaymentMethod>[];
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .whereType<Map<String, dynamic>>()
          .map(PaymentMethod.fromJson)
          .toList();
    } catch (_) {
      state = const <PaymentMethod>[];
    }
  }

  Future<void> _persist() async {
    final String raw =
        jsonEncode(state.map((PaymentMethod m) => m.toJson()).toList());
    await _storage.writeString(_kPaymentMethodsKey, raw);
  }

  Future<PaymentMethod> add({
    required String label,
    required String provider,
    required String phone,
  }) async {
    final PaymentMethod method = PaymentMethod(
      id: _uuid.v4(),
      label: label.trim(),
      provider: provider,
      phone: phone.trim(),
    );
    state = <PaymentMethod>[...state, method];
    await _persist();
    return method;
  }

  Future<void> update(PaymentMethod updated) async {
    state = state
        .map((PaymentMethod m) => m.id == updated.id ? updated : m)
        .toList();
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((PaymentMethod m) => m.id != id).toList();
    await _persist();
  }
}
