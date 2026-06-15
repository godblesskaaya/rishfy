import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/domain/payment_method.dart';
import '../../data/datasources/wallet_remote_datasource.dart';
import '../../data/models/wallet_models.dart';

final Provider<WalletRemoteDataSource> walletDataSourceProvider =
    Provider<WalletRemoteDataSource>(
  (Ref ref) => WalletRemoteDataSource(ref.read(dioClientProvider)),
);

final FutureProvider<DriverWalletSnapshot> driverWalletProvider =
    FutureProvider<DriverWalletSnapshot>((Ref ref) async {
  final String driverId = _currentDriverId(ref);
  final WalletRemoteDataSource ds = ref.read(walletDataSourceProvider);
  final DriverEarningsStats stats = await ds.getDriverEarnings(driverId);
  final List<DriverPayout> payouts = await ds.listDriverPayouts(driverId);
  return DriverWalletSnapshot(stats: stats, payouts: payouts);
});

final Provider<AsyncValue<DriverEarningsStats>> driverEarningsStatsProvider =
    Provider<AsyncValue<DriverEarningsStats>>((Ref ref) {
  return ref.watch(driverWalletProvider).whenData(
        (DriverWalletSnapshot wallet) => wallet.stats,
      );
});

final Provider<AsyncValue<List<DriverPayout>>> driverPayoutHistoryProvider =
    Provider<AsyncValue<List<DriverPayout>>>((Ref ref) {
  return ref.watch(driverWalletProvider).whenData(
        (DriverWalletSnapshot wallet) => wallet.payouts,
      );
});

final FutureProviderFamily<DriverPayoutDetail, String> driverPayoutDetailProvider =
    FutureProviderFamily<DriverPayoutDetail, String>(
  (Ref ref, String payoutId) async {
    final String driverId = _currentDriverId(ref);
    final WalletRemoteDataSource ds = ref.read(walletDataSourceProvider);
    return ds.getDriverPayoutDetail(driverId: driverId, payoutId: payoutId);
  },
);

class RequestPayoutState {
  const RequestPayoutState({
    this.loading = false,
    this.error,
    this.completed,
  });

  final bool loading;
  final String? error;
  final DriverPayout? completed;
}

final AutoDisposeStateNotifierProvider<RequestPayoutNotifier,
        RequestPayoutState> requestPayoutProvider =
    StateNotifierProvider.autoDispose<RequestPayoutNotifier,
        RequestPayoutState>(
  (Ref ref) => RequestPayoutNotifier(ref),
);

class RequestPayoutNotifier extends StateNotifier<RequestPayoutState> {
  RequestPayoutNotifier(this._ref) : super(const RequestPayoutState());

  final Ref _ref;

  Future<void> request(PaymentMethod method) async {
    if (method.phone.trim().isEmpty) {
      state = const RequestPayoutState(error: 'Choose a payout phone number.');
      return;
    }

    state = const RequestPayoutState(loading: true);
    try {
      final String driverId = _currentDriverId(_ref);
      final WalletRemoteDataSource ds = _ref.read(walletDataSourceProvider);
      final DriverPayout payout = await ds.requestDriverPayout(
        driverId: driverId,
        payoutMethod: method.provider,
        payoutPhone: method.phone,
      );
      state = RequestPayoutState(completed: payout);
      _ref.invalidate(driverWalletProvider);
    } catch (e) {
      state = RequestPayoutState(error: _payoutErrorMessage(e));
    }
  }

  void clear() => state = const RequestPayoutState();
}

String _currentDriverId(Ref ref) {
  final String? driverId = ref.read(currentUserProvider)?.userId;
  if (driverId == null || driverId.isEmpty) {
    throw const UnauthorizedException(message: 'Missing current driver.');
  }
  return driverId;
}

String _payoutErrorMessage(Object e) {
  if (e is DioException) {
    final dynamic errorCode = e.response?.data is Map<String, dynamic>
        ? (e.response!.data as Map<String, dynamic>)['error']
        : null;
    if (errorCode == 'NO_PAYABLE_BALANCE') {
      return 'There is no available balance to withdraw yet.';
    }
    if (errorCode == 'VALIDATION_ERROR') {
      return 'Check the payout method and phone number.';
    }
    if (e.error is AppException) {
      return (e.error! as AppException).message;
    }
  }
  if (e is AppException) return e.message;
  return 'Could not request payout.';
}
