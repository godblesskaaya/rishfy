import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routes/data/models/route_models.dart';
import '../../data/datasources/profile_remote_datasource.dart';
import '../../domain/blocked_user.dart';
import '../../domain/favorite_driver.dart';
import '../../domain/public_driver_profile.dart';
import '../../domain/support_case.dart';

final myVehiclesProvider =
    FutureProvider.autoDispose<List<DriverVehicleOption>>((Ref ref) async {
  final ProfileRemoteDataSource ds = ref.read(profileRemoteDataSourceProvider);
  return ds.listMyVehicles();
});

final favoriteDriversProvider =
    FutureProvider.autoDispose<List<FavoriteDriver>>((Ref ref) async {
  final ProfileRemoteDataSource ds = ref.read(profileRemoteDataSourceProvider);
  return ds.listFavoriteDrivers();
});

final blockedUsersProvider =
    FutureProvider.autoDispose<List<BlockedUser>>((Ref ref) async {
  final ProfileRemoteDataSource ds = ref.read(profileRemoteDataSourceProvider);
  return ds.listBlockedUsers();
});

final publicDriverProvider =
    FutureProvider.autoDispose.family<PublicDriverProfile, String>((Ref ref, String driverId) {
  final ProfileRemoteDataSource ds = ref.read(profileRemoteDataSourceProvider);
  return ds.getPublicDriver(driverId);
});

final supportCasesProvider =
    FutureProvider.autoDispose<List<SupportCase>>((Ref ref) async {
  final ProfileRemoteDataSource ds = ref.read(profileRemoteDataSourceProvider);
  return ds.listSupportCases();
});

enum FavoriteDriverActionStatus { idle, loading, success, failed }

class FavoriteDriverActionState {
  const FavoriteDriverActionState({
    this.status = FavoriteDriverActionStatus.idle,
    this.error,
  });

  final FavoriteDriverActionStatus status;
  final String? error;
}

enum BlockedUserActionStatus { idle, loading, success, failed }

class BlockedUserActionState {
  const BlockedUserActionState({
    this.status = BlockedUserActionStatus.idle,
    this.error,
  });

  final BlockedUserActionStatus status;
  final String? error;
}

enum SupportCaseActionStatus { idle, loading, success, failed }

class SupportCaseActionState {
  const SupportCaseActionState({
    this.status = SupportCaseActionStatus.idle,
    this.error,
  });

  final SupportCaseActionStatus status;
  final String? error;
}

final supportCaseActionProvider = StateNotifierProvider.autoDispose<
    SupportCaseActionNotifier, SupportCaseActionState>(
  (Ref ref) => SupportCaseActionNotifier(ref),
);

class SupportCaseActionNotifier
    extends StateNotifier<SupportCaseActionState> {
  SupportCaseActionNotifier(this._ref)
      : super(const SupportCaseActionState());

  final Ref _ref;

  Future<void> create({
    required String subject,
    required String message,
    required String category,
    String? bookingId,
  }) async {
    state = const SupportCaseActionState(
      status: SupportCaseActionStatus.loading,
    );
    try {
      await _ref.read(profileRemoteDataSourceProvider).createSupportCase(
            subject: subject,
            message: message,
            category: category,
            bookingId: bookingId,
          );
      _ref.invalidate(supportCasesProvider);
      state = const SupportCaseActionState(
        status: SupportCaseActionStatus.success,
      );
    } catch (_) {
      state = const SupportCaseActionState(
        status: SupportCaseActionStatus.failed,
        error: 'Could not submit your support case.',
      );
    }
  }
}

final blockedUserActionProvider = StateNotifierProvider.autoDispose<
    BlockedUserActionNotifier, BlockedUserActionState>(
  (Ref ref) => BlockedUserActionNotifier(ref),
);

class BlockedUserActionNotifier extends StateNotifier<BlockedUserActionState> {
  BlockedUserActionNotifier(this._ref)
      : super(const BlockedUserActionState());

  final Ref _ref;

  Future<void> block(String userId, {String? reason}) async {
    await _run(() => _dataSource.blockUser(userId, reason: reason));
  }

  Future<void> unblock(String userId) async {
    await _run(() => _dataSource.unblockUser(userId));
  }

  ProfileRemoteDataSource get _dataSource =>
      _ref.read(profileRemoteDataSourceProvider);

  Future<void> _run(Future<void> Function() action) async {
    state = const BlockedUserActionState(
      status: BlockedUserActionStatus.loading,
    );
    try {
      await action();
      _ref.invalidate(blockedUsersProvider);
      state = const BlockedUserActionState(
        status: BlockedUserActionStatus.success,
      );
    } catch (_) {
      state = const BlockedUserActionState(
        status: BlockedUserActionStatus.failed,
        error: 'Could not update blocked users.',
      );
    }
  }
}

final favoriteDriverActionProvider = StateNotifierProvider.autoDispose<
    FavoriteDriverActionNotifier, FavoriteDriverActionState>(
  (Ref ref) => FavoriteDriverActionNotifier(ref),
);

class FavoriteDriverActionNotifier
    extends StateNotifier<FavoriteDriverActionState> {
  FavoriteDriverActionNotifier(this._ref)
      : super(const FavoriteDriverActionState());

  final Ref _ref;

  Future<void> add(String driverUserId) async {
    await _run(() => _dataSource.addFavoriteDriver(driverUserId));
  }

  Future<void> remove(String driverUserId) async {
    await _run(() => _dataSource.removeFavoriteDriver(driverUserId));
  }

  ProfileRemoteDataSource get _dataSource =>
      _ref.read(profileRemoteDataSourceProvider);

  Future<void> _run(Future<void> Function() action) async {
    state = const FavoriteDriverActionState(
      status: FavoriteDriverActionStatus.loading,
    );
    try {
      await action();
      _ref.invalidate(favoriteDriversProvider);
      state = const FavoriteDriverActionState(
        status: FavoriteDriverActionStatus.success,
      );
    } catch (_) {
      state = const FavoriteDriverActionState(
        status: FavoriteDriverActionStatus.failed,
        error: 'Could not update favorite drivers.',
      );
    }
  }
}
