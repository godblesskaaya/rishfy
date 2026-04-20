/// Application-wide constants. Avoid magic numbers elsewhere.
class AppConstants {
  AppConstants._();

  // Spacing (8pt grid)
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  // Border radius
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusFull = 999;

  // Durations
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // Network
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration apiConnectTimeout = Duration(seconds: 10);
  static const int maxRetries = 3;

  // Business rules
  static const int otpLength = 6;
  static const Duration otpResendCooldown = Duration(seconds: 60);
  static const Duration otpValidity = Duration(minutes: 5);
  static const int maxSeatsPerBooking = 6;
  static const Duration cancellationFreeWindow = Duration(hours: 2);
  static const int platformFeePct = 15;

  // Location tracking
  static const Duration locationSamplingInterval = Duration(seconds: 30);
  static const double locationAccuracyThresholdMeters = 50;

  // Storage keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyDeviceId = 'device_id';
  static const String keyActiveRole = 'active_role';
  static const String keyLocale = 'locale';
  static const String keyOnboardingComplete = 'onboarding_complete';
  static const String keyBiometricEnabled = 'biometric_enabled';
}
