import '../../domain/entities/user.dart';

class UserDto {
  UserDto({
    required this.userId,
    required this.phoneNumber,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isVerified,
    this.email,
    this.profilePictureUrl,
    this.ratingAverage,
    this.ratingCount,
    this.language,
  });

  final String userId;
  final String phoneNumber;
  final String firstName;
  final String lastName;
  final String? email;
  final String? profilePictureUrl;
  final String role;
  final bool isVerified;
  final double? ratingAverage;
  final int? ratingCount;
  final String? language;

  factory UserDto.fromJson(Map<String, dynamic> json) {
    return UserDto(
      userId: json['user_id'] as String,
      phoneNumber: json['phone_number'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String?,
      profilePictureUrl: json['profile_picture_url'] as String?,
      role: json['role'] as String? ?? 'passenger',
      isVerified: json['is_verified'] as bool? ?? false,
      ratingAverage: (json['rating_average'] as num?)?.toDouble(),
      ratingCount: json['rating_count'] as int?,
      language: json['language'] as String?,
    );
  }

  User toDomain() {
    return User(
      userId: userId,
      phoneNumber: phoneNumber,
      firstName: firstName,
      lastName: lastName,
      email: email,
      profilePictureUrl: profilePictureUrl,
      role: UserRole.fromString(role),
      isVerified: isVerified,
      ratingAverage: ratingAverage ?? 0.0,
      ratingCount: ratingCount ?? 0,
      language: language ?? 'en',
    );
  }
}

class AuthTokensDto {
  AuthTokensDto({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn; // seconds
  final String tokenType;

  factory AuthTokensDto.fromJson(Map<String, dynamic> json) {
    return AuthTokensDto(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int? ?? 900,
      tokenType: json['token_type'] as String? ?? 'Bearer',
    );
  }

  DateTime get expiresAt => DateTime.now().add(Duration(seconds: expiresIn));
}

class LoginResponseDto {
  LoginResponseDto({
    required this.tokens,
    required this.user,
  });

  final AuthTokensDto tokens;
  final UserDto user;

  factory LoginResponseDto.fromJson(Map<String, dynamic> json) {
    return LoginResponseDto(
      tokens: AuthTokensDto.fromJson(json),
      user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class OtpRequestResponseDto {
  OtpRequestResponseDto({
    required this.otpReference,
    required this.expiresInSeconds,
    required this.cooldownSeconds,
  });

  final String otpReference;
  final int expiresInSeconds;
  final int cooldownSeconds;

  factory OtpRequestResponseDto.fromJson(Map<String, dynamic> json) {
    return OtpRequestResponseDto(
      otpReference: json['otp_reference'] as String,
      expiresInSeconds: json['expires_in_seconds'] as int? ?? 300,
      cooldownSeconds: json['cooldown_seconds'] as int? ?? 60,
    );
  }
}
