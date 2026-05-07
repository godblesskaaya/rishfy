import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_logger.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Immutable auth state. Held by [AuthController].
class AuthState {
  const AuthState({
    required this.isAuthenticated,
    this.user,
    this.session,
  });

  final bool isAuthenticated;
  final User? user;
  final AuthSession? session;

  const AuthState.unauthenticated()
      : isAuthenticated = false,
        user = null,
        session = null;

  AuthState.authenticated(AuthSession session)
      : isAuthenticated = true,
        user = session.user,
        session = session;

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    AuthSession? session,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      session: session ?? this.session,
    );
  }
}

final Provider<AuthRemoteDataSource> authRemoteDataSourceProvider =
    Provider<AuthRemoteDataSource>((Ref ref) {
  return AuthRemoteDataSource(ref.read(dioClientProvider));
});

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
  return AuthRepositoryImpl(
    remote: ref.read(authRemoteDataSourceProvider),
    storage: ref.read(secureStorageProvider),
  );
});

final AsyncNotifierProvider<AuthController, AuthState> authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  late AuthRepository _repo;

  @override
  Future<AuthState> build() async {
    _repo = ref.read(authRepositoryProvider);
    return _bootstrap();
  }

  Future<AuthState> _bootstrap() async {
    try {
      final AuthSession? session = await _repo.getCurrentSession();
      if (session == null) {
        return const AuthState.unauthenticated();
      }
      return AuthState.authenticated(session);
    } catch (e, s) {
      AppLogger.error('Bootstrap failed', error: e, stackTrace: s);
      return const AuthState.unauthenticated();
    }
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    state = await AsyncValue.guard(() async {
      final AuthSession session = await _repo.login(
        identifier: identifier,
        password: password,
      );
      return AuthState.authenticated(session);
    });
  }

  Future<PendingRegistration> register({
    required String phoneNumber,
    required String password,
    String? fullName,
    String? email,
  }) {
    return _repo.register(
      phoneNumber: phoneNumber,
      password: password,
      fullName: fullName,
      email: email,
    );
  }

  Future<void> verifyOtp({
    required String userId,
    required String otpCode,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    state = await AsyncValue.guard(() async {
      final AuthSession session = await _repo.verifyOtp(
        userId: userId,
        otpCode: otpCode,
      );
      return AuthState.authenticated(session);
    });
  }

  Future<bool> refreshSession() async {
    try {
      final AuthSession? newSession = await _repo.refreshSession();
      if (newSession == null) {
        return state.valueOrNull?.isAuthenticated ?? false;
      }
      state = AsyncValue<AuthState>.data(AuthState.authenticated(newSession));
      return true;
    } catch (e, s) {
      AppLogger.error('Session refresh failed', error: e, stackTrace: s);
      return false;
    }
  }

  Future<void> logout() async {
    state = const AsyncValue<AuthState>.loading();
    try {
      await _repo.logout();
    } finally {
      state = const AsyncValue<AuthState>.data(AuthState.unauthenticated());
    }
  }

  Future<void> forceLogout() async {
    state = const AsyncValue<AuthState>.data(AuthState.unauthenticated());
    await ref.read(secureStorageProvider).clear();
  }

  void updateUser(User updatedUser) {
    final AuthState? current = state.valueOrNull;
    if (current?.session == null) return;

    final AuthSession newSession = AuthSession(
      accessToken: current!.session!.accessToken,
      refreshToken: current.session!.refreshToken,
      expiresAt: current.session!.expiresAt,
      user: updatedUser,
    );
    state = AsyncValue<AuthState>.data(AuthState.authenticated(newSession));
  }
}

final Provider<User?> currentUserProvider = Provider<User?>((Ref ref) {
  return ref.watch(authControllerProvider).valueOrNull?.user;
});

final Provider<bool> canSwitchRolesProvider = Provider<bool>((Ref ref) {
  final User? user = ref.watch(currentUserProvider);
  return user?.canSwitchRoles ?? false;
});
