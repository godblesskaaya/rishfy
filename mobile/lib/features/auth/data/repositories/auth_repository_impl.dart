import 'package:uuid/uuid.dart';

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
  Future<String> requestOtp({
    required String phoneNumber,
    required String purpose,
  }) async {
    final OtpRequestResponseDto response = await _remote.requestOtp(
      phoneNumber: phoneNumber,
      purpose: purpose,
    );
    return response.otpReference;
  }

  @override
  Future<AuthSession> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    required String otpReference,
  }) async {
    final String deviceId = await _ensureDeviceId();
    final LoginResponseDto response = await _remote.verifyOtp(
      phoneNumber: phoneNumber,
      otpCode: otpCode,
      otpReference: otpReference,
      deviceId: deviceId,
    );

    final AuthSession session = _toSession(response);
    await _persist(session);
    return session;
  }

  @override
  Future<AuthSession> register({
    required String phoneNumber,
    required String firstName,
    required String lastName,
    required String otpCode,
    required String otpReference,
    String? email,
  }) async {
    final String deviceId = await _ensureDeviceId();
    final LoginResponseDto response = await _remote.register(
      phoneNumber: phoneNumber,
      firstName: firstName,
      lastName: lastName,
      otpCode: otpCode,
      otpReference: otpReference,
      deviceId: deviceId,
      email: email,
    );

    final AuthSession session = _toSession(response);
    await _persist(session);
    return session;
  }

  @override
  Future<AuthSession?> refreshSession() async {
    final String? refreshToken = await _storage.readRefreshToken();
    final String? userId = await _storage.readUserId();
    if (refreshToken == null || userId == null) {
      return null;
    }

    try {
      final String deviceId = await _ensureDeviceId();
      final AuthTokensDto tokens = await _remote.refresh(
        refreshToken: refreshToken,
        deviceId: deviceId,
      );

      await _storage.writeAccessToken(tokens.accessToken);
      await _storage.writeRefreshToken(tokens.refreshToken);

      // For refresh, we don't have the full user object — callers should
      // reuse the existing user and just update tokens. Return null to signal
      // that the controller should rebuild from storage.
      return null;
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

    // We don't cache the full user object locally; it's re-fetched by the
    // user-service on app start via the profile endpoint. Return a minimal
    // session here — the controller will refresh user data.
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      // Expiry is unknown without parsing the JWT; assume valid and let the
      // AuthInterceptor trigger refresh on 401.
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      user: User(
        userId: userId,
        phoneNumber: '', // Filled in by profile fetch
        firstName: '',
        lastName: '',
        role: UserRole.passenger,
        isVerified: true,
      ),
    );
  }

  @override
  Future<bool> phoneExists(String phoneNumber) {
    return _remote.checkPhoneExists(phoneNumber);
  }

  // ---------------- helpers ----------------

  Future<String> _ensureDeviceId() async {
    String? id = await _storage.readDeviceId();
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _storage.writeDeviceId(id);
    }
    return id;
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
