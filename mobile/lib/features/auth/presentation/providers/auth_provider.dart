import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_logger.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../profile/data/datasources/profile_remote_datasource.dart';
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
  late ProfileRemoteDataSource _profileRemote;

  @override
  Future<AuthState> build() async {
    _repo = ref.read(authRepositoryProvider);
    _profileRemote = ref.read(profileRemoteDataSourceProvider);
    return _bootstrap();
  }

  Future<AuthState> _bootstrap() async {
    try {
      final AuthSession? session = await _repo.getCurrentSession();
      if (session == null) {
        return const AuthState.unauthenticated();
      }
      final AuthSession hydrated = await _hydrateSession(session);
      return AuthState.authenticated(hydrated);
    } catch (e, s) {
      AppLogger.error('Bootstrap failed', error: e, stackTrace: s);
      return const AuthState.unauthenticated();
    }
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    AppLogger.info('AuthController.login start for $identifier');
    final AuthState previousState =
        state.valueOrNull ?? const AuthState.unauthenticated();
    state = const AsyncValue<AuthState>.loading();
    try {
      final AuthSession session = await _repo.login(
        identifier: identifier,
        password: password,
      );
      final AuthSession hydrated = await _hydrateSession(session);
      AppLogger.info(
        'AuthController.login success for ${hydrated.user.userId}',
      );
      state = AsyncValue<AuthState>.data(AuthState.authenticated(hydrated));
    } catch (e, s) {
      AppLogger.warn('AuthController.login failed', error: e, stackTrace: s);
      state = AsyncValue<AuthState>.data(previousState);
      Error.throwWithStackTrace(e, s);
    }
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

  Future<void> requestPasswordReset({required String identifier}) {
    return _repo.requestPasswordReset(identifier: identifier);
  }

  Future<void> confirmPasswordReset({
    required String identifier,
    required String otpCode,
    required String newPassword,
  }) {
    return _repo.confirmPasswordReset(
      identifier: identifier,
      otpCode: otpCode,
      newPassword: newPassword,
    );
  }

  Future<void> resendOtp({
    required String userId,
    String purpose = 'register',
  }) {
    return _repo.resendOtp(userId: userId, purpose: purpose);
  }

  Future<void> verifyOtp({
    required String userId,
    required String otpCode,
  }) async {
    AppLogger.info('AuthController.verifyOtp start for $userId');
    final AuthState previousState =
        state.valueOrNull ?? const AuthState.unauthenticated();
    state = const AsyncValue<AuthState>.loading();
    try {
      final AuthSession session = await _repo.verifyOtp(
        userId: userId,
        otpCode: otpCode,
      );
      final AuthSession hydrated = await _hydrateSession(session);
      AppLogger.info(
        'AuthController.verifyOtp success for ${hydrated.user.userId}',
      );
      state = AsyncValue<AuthState>.data(AuthState.authenticated(hydrated));
    } catch (e, s) {
      AppLogger.warn('AuthController.verifyOtp failed', error: e, stackTrace: s);
      state = AsyncValue<AuthState>.data(previousState);
      Error.throwWithStackTrace(e, s);
    }
  }

  Future<bool> refreshSession() async {
    try {
      AppLogger.info('AuthController.refreshSession start');
      final AuthSession? newSession = await _repo.refreshSession();
      if (newSession == null) {
        AppLogger.warn('AuthController.refreshSession returned null');
        return state.valueOrNull?.isAuthenticated ?? false;
      }
      final AuthSession hydrated = await _hydrateSession(newSession);
      AppLogger.info(
        'AuthController.refreshSession success for ${hydrated.user.userId}',
      );
      state = AsyncValue<AuthState>.data(AuthState.authenticated(hydrated));
      return true;
    } catch (e, s) {
      AppLogger.error('Session refresh failed', error: e, stackTrace: s);
      return false;
    }
  }

  Future<void> logout() async {
    state = const AsyncValue<AuthState>.loading();
    try {
      AppLogger.info('AuthController.logout start');
      await _repo.logout();
    } finally {
      AppLogger.info('AuthController.logout complete');
      state = const AsyncValue<AuthState>.data(AuthState.unauthenticated());
    }
  }

  Future<void> forceLogout() async {
    AppLogger.warn('AuthController.forceLogout triggered');
    state = const AsyncValue<AuthState>.data(AuthState.unauthenticated());
    await ref.read(secureStorageProvider).clear();
  }

  Future<void> syncCurrentUser() async {
    final AuthSession? session = state.valueOrNull?.session;
    if (session == null) return;
    final AuthSession hydrated = await _hydrateSession(session);
    state = AsyncValue<AuthState>.data(AuthState.authenticated(hydrated));
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
    unawaited(_repo.cacheUser(updatedUser));
    state = AsyncValue<AuthState>.data(AuthState.authenticated(newSession));
  }

  Future<AuthSession> _hydrateSession(AuthSession session) async {
    try {
      final User currentUser = await _profileRemote.getCurrentUser();
      await _repo.cacheUser(currentUser);
      return AuthSession(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        expiresAt: session.expiresAt,
        user: currentUser,
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'AuthController._hydrateSession fell back to auth payload user',
        error: error,
        stackTrace: stackTrace,
      );
      return session;
    }
  }
}

final Provider<User?> currentUserProvider = Provider<User?>((Ref ref) {
  return ref.watch(authControllerProvider).valueOrNull?.user;
});

final Provider<bool> canSwitchRolesProvider = Provider<bool>((Ref ref) {
  final User? user = ref.watch(currentUserProvider);
  return user?.canSwitchRoles ?? false;
});
