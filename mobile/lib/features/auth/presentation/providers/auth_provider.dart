import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_logger.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

// ============================================================================
// State
// ============================================================================

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

// ============================================================================
// DI
// ============================================================================

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

// ============================================================================
// Controller
// ============================================================================

final AsyncNotifierProvider<AuthController, AuthState> authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  late AuthRepository _repo;

  @override
  Future<AuthState> build() async {
    _repo = ref.read(authRepositoryProvider);
    return _bootstrap();
  }

  /// Check for persisted session on app start.
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

  // --------------------------- Flows ---------------------------------------

  /// Returns the OTP reference ID.
  Future<String> requestOtp({
    required String phoneNumber,
    required String purpose,
  }) async {
    return _repo.requestOtp(phoneNumber: phoneNumber, purpose: purpose);
  }

  /// Login by OTP. Updates [state] on success.
  Future<void> loginWithOtp({
    required String phoneNumber,
    required String otpCode,
    required String otpReference,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    state = await AsyncValue.guard(() async {
      final AuthSession session = await _repo.verifyOtp(
        phoneNumber: phoneNumber,
        otpCode: otpCode,
        otpReference: otpReference,
      );
      return AuthState.authenticated(session);
    });
  }

  /// Register a new user. Updates [state] on success.
  Future<void> register({
    required String phoneNumber,
    required String firstName,
    required String lastName,
    required String otpCode,
    required String otpReference,
    String? email,
  }) async {
    state = const AsyncValue<AuthState>.loading();
    state = await AsyncValue.guard(() async {
      final AuthSession session = await _repo.register(
        phoneNumber: phoneNumber,
        firstName: firstName,
        lastName: lastName,
        otpCode: otpCode,
        otpReference: otpReference,
        email: email,
      );
      return AuthState.authenticated(session);
    });
  }

  /// Refresh tokens using the stored refresh token.
  /// Returns true on success.
  Future<bool> refreshSession() async {
    try {
      final AuthSession? newSession = await _repo.refreshSession();
      if (newSession == null) {
        // Token refresh updated storage but didn't return a full session —
        // keep current user, just mark authenticated.
        return state.valueOrNull?.isAuthenticated ?? false;
      }
      state = AsyncValue<AuthState>.data(AuthState.authenticated(newSession));
      return true;
    } catch (e, s) {
      AppLogger.error('Session refresh failed', error: e, stackTrace: s);
      return false;
    }
  }

  /// User-initiated logout.
  Future<void> logout() async {
    state = const AsyncValue<AuthState>.loading();
    try {
      await _repo.logout();
    } finally {
      state = const AsyncValue<AuthState>.data(AuthState.unauthenticated());
    }
  }

  /// Forced logout — triggered by the AuthInterceptor after refresh failure.
  /// Does NOT call the server (that would just fail again); just clears local state.
  Future<void> forceLogout() async {
    state = const AsyncValue<AuthState>.data(AuthState.unauthenticated());
    await ref.read(secureStorageProvider).clear();
  }

  /// Update the cached user (e.g., after profile edit).
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

// ============================================================================
// Convenience selectors
// ============================================================================

/// Current authenticated user, or null if unauthenticated.
final Provider<User?> currentUserProvider = Provider<User?>((Ref ref) {
  return ref.watch(authControllerProvider).valueOrNull?.user;
});

/// True if user can switch between passenger and driver roles.
final Provider<bool> canSwitchRolesProvider = Provider<bool>((Ref ref) {
  final User? user = ref.watch(currentUserProvider);
  return user?.canSwitchRoles ?? false;
});
