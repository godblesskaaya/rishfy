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
    final LoginResponseDto response = await _remote.login(
      identifier: identifier,
      password: password,
    );

    final AuthSession session = _toSession(response);
    await _persist(session);
    return session;
  }

  @override
  Future<PendingRegistration> register({
    required String phoneNumber,
    required String password,
    String? fullName,
    String? email,
  }) async {
    final RegistrationResponseDto response = await _remote.register(
      phoneNumber: phoneNumber,
      password: password,
      fullName: fullName,
      email: email,
    );

    return PendingRegistration(
      userId: response.user.userId,
      phoneNumber: response.user.phoneNumber.isEmpty
          ? phoneNumber
          : response.user.phoneNumber,
      email: response.user.email ?? email,
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

    if (accessToken == null || refreshToken == null || userId == null) {
      return null;
    }

    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      user: User(
        userId: userId,
        phoneNumber: '',
        firstName: '',
        lastName: '',
        role: UserRole.passenger,
        isVerified: true,
      ),
    );
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
  }
}
