import '../entities/user.dart';

/// Contract for authentication operations.
/// Concrete impl lives in data/repositories/auth_repository_impl.dart
abstract class AuthRepository {
  /// Request an OTP for the given phone number.
  /// Returns the OTP reference ID used in [verifyOtp].
  Future<String> requestOtp({
    required String phoneNumber,
    required String purpose, // 'registration' | 'login' | 'password_reset'
  });

  /// Verify OTP and log in. Throws on failure.
  /// Returns the authenticated session.
  Future<AuthSession> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    required String otpReference,
  });

  /// Register a new user after OTP verification.
  Future<AuthSession> register({
    required String phoneNumber,
    required String firstName,
    required String lastName,
    required String otpCode,
    required String otpReference,
    String? email,
  });

  /// Refresh the access token using the stored refresh token.
  /// Returns the new session, or null if refresh failed.
  Future<AuthSession?> refreshSession();

  /// Log out — invalidates the refresh token server-side and clears local storage.
  Future<void> logout();

  /// Get the current cached session, if any.
  Future<AuthSession?> getCurrentSession();

  /// Check if a phone number is registered. Used during login flow.
  Future<bool> phoneExists(String phoneNumber);
}
