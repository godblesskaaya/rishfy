import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/profile_remote_datasource.dart';
import '../../domain/payment_method.dart';

final StateNotifierProvider<PaymentMethodsNotifier, List<PaymentMethod>>
    paymentMethodsProvider =
    StateNotifierProvider<PaymentMethodsNotifier, List<PaymentMethod>>(
  (Ref ref) => PaymentMethodsNotifier(ref.read(profileRemoteDataSourceProvider)),
);

class PaymentMethodsNotifier extends StateNotifier<List<PaymentMethod>> {
  PaymentMethodsNotifier(this._dataSource) : super(const <PaymentMethod>[]) {
    unawaited(refresh());
  }

  final ProfileRemoteDataSource _dataSource;

  Future<void> refresh() async {
    state = await _dataSource.listPaymentMethods();
  }

  Future<PaymentMethod> add({
    required String label,
    required String provider,
    required String phone,
    bool isDefault = false,
  }) async {
    final PaymentMethod method = await _dataSource.addPaymentMethod(
      label: label,
      provider: provider,
      phone: phone,
      isDefault: isDefault,
    );
    await refresh();
    return method;
  }

  Future<void> update(PaymentMethod updated) async {
    await _dataSource.updatePaymentMethod(updated);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _dataSource.deletePaymentMethod(id);
    state = state.where((PaymentMethod m) => m.id != id).toList();
  }
}
