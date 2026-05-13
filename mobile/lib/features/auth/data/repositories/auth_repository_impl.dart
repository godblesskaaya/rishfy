import 'dart:convert';

import '../../../../core/constants/app_logger.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_models.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required SecureStorage storage,
  })  : _remote = remote,
        _storage = storage;

  final AuthRemoteDataSource _remote;
  final SecureStorage _storage;

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    AppLogger.info('AuthRepository.login request for $identifier');
    final LoginResponseDto response = await _remote.login(
      identifier: identifier,
      password: password,
    );

    final AuthSession session = _toSession(response);
    await _persist(session);
    AppLogger.info(
      'AuthRepository.login persisted session for ${session.user.userId}',
    );
    return session;
  }

  @override
  Future<PendingRegistration> register({
    required String email,
    required String password,
    String? fullName,
    String? phoneNumber,
  }) async {
    final RegistrationResponseDto response = await _remote.register(
      email: email,
      password: password,
      fullName: fullName,
      phoneNumber: phoneNumber,
    );

    return PendingRegistration(
      userId: response.user.userId,
      email: response.user.email ?? email,
      phoneNumber: response.user.phoneNumber.isEmpty ? phoneNumber : response.user.phoneNumber,
      expiresAt: response.otpExpiresAt,
    );
  }

  @override
  Future<AuthSession> verifyOtp({
    required String userId,
    required String otpCode,
  }) async {
    final LoginResponseDto response = await _remote.verifyOtp(
      userId: userId,
      otpCode: otpCode,
    );

    final AuthSession session = _toSession(response);
    await _persist(session);
    return session;
  }

  @override
  Future<AuthSession?> refreshSession() async {
    final String? refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) {
      AppLogger.warn('AuthRepository.refreshSession missing refresh token');
      return null;
    }

    try {
      final RefreshResponseDto response = await _remote.refresh(
        refreshToken: refreshToken,
      );

      await _storage.writeAccessToken(response.tokens.accessToken);
      await _storage.writeRefreshToken(response.tokens.refreshToken);

      if (response.user == null) {
        return null;
      }

      final AuthSession current = await _requireCachedSession();
      final AuthSession refreshed = AuthSession(
        accessToken: response.tokens.accessToken,
        refreshToken: response.tokens.refreshToken,
        expiresAt: response.tokens.expiresAt,
        user: response.user!.toDomain().copyWith(
              phoneNumber: response.user!.phoneNumber.isEmpty
                  ? current.user.phoneNumber
                  : response.user!.phoneNumber,
            ),
      );
      await _persist(refreshed);
      return refreshed;
    } catch (e, s) {
      AppLogger.error('Refresh failed', error: e, stackTrace: s);
      return null;
    }
  }

  @override
  Future<void> logout() async {
    final String? refreshToken = await _storage.readRefreshToken();
    if (refreshToken != null) {
      await _remote.logout(refreshToken: refreshToken);
    }
    await _storage.clear();
  }

  @override
  Future<AuthSession?> getCurrentSession() async {
    final String? accessToken = await _storage.readAccessToken();
    final String? refreshToken = await _storage.readRefreshToken();
    final String? userId = await _storage.readUserId();
    final String? cachedUserSnapshot = await _storage.readUserSnapshot();

    if (accessToken == null || refreshToken == null || userId == null) {
      AppLogger.info('AuthRepository.getCurrentSession cache miss');
      return null;
    }

    User restoredUser;
    if (cachedUserSnapshot != null && cachedUserSnapshot.isNotEmpty) {
      try {
        final Object? raw = jsonDecode(cachedUserSnapshot);
        if (raw is Map<String, dynamic>) {
          restoredUser = UserDto.fromJson(raw).toDomain();
        } else {
          restoredUser = _fallbackCachedUser(userId);
        }
      } catch (error, stackTrace) {
        AppLogger.warn(
          'AuthRepository.getCurrentSession failed to decode cached user',
          error: error,
          stackTrace: stackTrace,
        );
        restoredUser = _fallbackCachedUser(userId);
      }
    } else {
      restoredUser = _fallbackCachedUser(userId);
    }

    AppLogger.info('AuthRepository.getCurrentSession cache hit for $userId');
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      user: restoredUser,
    );
  }

  @override
  Future<void> requestPasswordReset({required String identifier}) {
    return _remote.requestPasswordReset(identifier: identifier);
  }

  @override
  Future<void> confirmPasswordReset({
    required String identifier,
    required String otpCode,
    required String newPassword,
  }) {
    return _remote.confirmPasswordReset(
      identifier: identifier,
      otpCode: otpCode,
      newPassword: newPassword,
    );
  }

  @override
  Future<void> resendOtp({
    required String userId,
    String purpose = 'register',
  }) {
    return _remote.resendOtp(userId: userId, purpose: purpose);
  }

  @override
  Future<void> cacheUser(User user) async {
    await _storage.writeUserSnapshot(jsonEncode(userToStorageJson(user)));
    AppLogger.info('AuthRepository.cacheUser updated snapshot for ${user.userId}');
  }

  Future<AuthSession> _requireCachedSession() async {
    final AuthSession? session = await getCurrentSession();
    if (session == null) {
      throw StateError('No cached session available during refresh.');
    }
    return session;
  }

  AuthSession _toSession(LoginResponseDto dto) {
    return AuthSession(
      accessToken: dto.tokens.accessToken,
      refreshToken: dto.tokens.refreshToken,
      expiresAt: dto.tokens.expiresAt,
      user: dto.user.toDomain(),
    );
  }

  Future<void> _persist(AuthSession session) async {
    await _storage.writeAccessToken(session.accessToken);
    await _storage.writeRefreshToken(session.refreshToken);
    await _storage.writeUserId(session.user.userId);
    await _storage.writeUserSnapshot(jsonEncode(userToStorageJson(session.user)));
    AppLogger.info(
      'AuthRepository._persist wrote secure storage for ${session.user.userId}',
    );
  }

  User _fallbackCachedUser(String userId) {
    return User(
      userId: userId,
      phoneNumber: '',
      firstName: '',
      lastName: '',
      role: UserRole.passenger,
      isVerified: true,
    );
  }
}
