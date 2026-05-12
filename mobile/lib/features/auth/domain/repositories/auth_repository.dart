import '../entities/user.dart';

/// Contract for authentication operations.
/// Concrete implementation lives in data/repositories/auth_repository_impl.dart.
abstract class AuthRepository {
  /// Start a password-based login flow.
  Future<AuthSession> login({
    required String identifier,
    required String password,
  });

  /// Create an account and trigger OTP delivery.
  Future<PendingRegistration> register({
    required String phoneNumber,
    required String password,
    String? fullName,
    String? email,
  });

  /// Complete registration by verifying the OTP code.
  Future<AuthSession> verifyOtp({
    required String userId,
    required String otpCode,
  });

  /// Refresh the access token using the stored refresh token.
  /// Returns the updated session when a user payload is available.
  Future<AuthSession?> refreshSession();

  /// Log out - invalidates the refresh token server-side and clears local storage.
  Future<void> logout();

  /// Get the current cached session, if any.
  Future<AuthSession?> getCurrentSession();

  /// Update the cached user profile without changing stored tokens.
  Future<void> cacheUser(User user);

  /// Request a password reset OTP for the given identifier (email or phone).
  Future<void> requestPasswordReset({required String identifier});

  /// Complete a password reset using the OTP that was sent.
  Future<void> confirmPasswordReset({
    required String identifier,
    required String otpCode,
    required String newPassword,
  });

  /// Re-issue an OTP for an in-flight registration or password reset.
  Future<void> resendOtp({
    required String userId,
    String purpose = 'register',
  });
}
