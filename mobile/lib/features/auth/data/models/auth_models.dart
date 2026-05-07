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
    final String fullName = _readString(
          json,
          <String>['fullName', 'full_name'],
        ) ??
        '';
    final List<String> nameParts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();

    final String firstName = _readString(
          json,
          <String>['firstName', 'first_name'],
        ) ??
        (nameParts.isNotEmpty ? nameParts.first : '');
    final String lastName = _readString(
          json,
          <String>['lastName', 'last_name'],
        ) ??
        (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '');

    return UserDto(
      userId: _readRequiredString(json, <String>['id', 'userId', 'user_id']),
      phoneNumber:
          _readString(json, <String>['phoneNumber', 'phone_number']) ?? '',
      firstName: firstName,
      lastName: lastName,
      email: _readString(json, <String>['email']),
      profilePictureUrl: _readString(
        json,
        <String>['profilePictureUrl', 'profile_picture_url'],
      ),
      role: _readString(json, <String>['role']) ?? 'passenger',
      isVerified: _readBool(json, <String>['isVerified', 'is_verified']) ??
          false,
      ratingAverage: _readNum(
        json,
        <String>['ratingAverage', 'rating_average'],
      )?.toDouble(),
      ratingCount:
          _readNum(json, <String>['ratingCount', 'rating_count'])?.toInt(),
      language: _readString(json, <String>['language']),
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
  final int expiresIn;
  final String tokenType;

  factory AuthTokensDto.fromJson(Map<String, dynamic> json) {
    return AuthTokensDto(
      accessToken: _readRequiredString(
        json,
        <String>['accessToken', 'access_token'],
      ),
      refreshToken: _readRequiredString(
        json,
        <String>['refreshToken', 'refresh_token'],
      ),
      expiresIn: _readNum(
            json,
            <String>['expiresInSeconds', 'expires_in_seconds', 'expires_in'],
          )?.toInt() ??
          900,
      tokenType:
          _readString(json, <String>['tokenType', 'token_type']) ?? 'Bearer',
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
    final Object? tokensJson = json['tokens'] ?? json;
    final Object? userJson = json['user'];
    if (tokensJson is! Map<String, dynamic> || userJson is! Map<String, dynamic>) {
      throw const FormatException('Missing auth response tokens or user.');
    }

    return LoginResponseDto(
      tokens: AuthTokensDto.fromJson(tokensJson),
      user: UserDto.fromJson(userJson),
    );
  }
}

class RefreshResponseDto {
  RefreshResponseDto({
    required this.tokens,
    this.user,
  });

  final AuthTokensDto tokens;
  final UserDto? user;

  factory RefreshResponseDto.fromJson(Map<String, dynamic> json) {
    final Object? tokensJson = json['tokens'] ?? json;
    final Object? userJson = json['user'];
    if (tokensJson is! Map<String, dynamic>) {
      throw const FormatException('Missing refresh response tokens.');
    }

    return RefreshResponseDto(
      tokens: AuthTokensDto.fromJson(tokensJson),
      user: userJson is Map<String, dynamic> ? UserDto.fromJson(userJson) : null,
    );
  }
}

class RegistrationResponseDto {
  RegistrationResponseDto({
    required this.user,
    this.otpExpiresAt,
  });

  final UserDto user;
  final DateTime? otpExpiresAt;

  factory RegistrationResponseDto.fromJson(Map<String, dynamic> json) {
    final Object? userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const FormatException('Missing registration response user.');
    }

    final String? otpExpiresAtRaw = _readString(
      json,
      <String>['otpExpiresAt', 'otp_expires_at'],
    );

    return RegistrationResponseDto(
      user: UserDto.fromJson(userJson),
      otpExpiresAt:
          otpExpiresAtRaw == null ? null : DateTime.tryParse(otpExpiresAtRaw),
    );
  }
}

String _readRequiredString(Map<String, dynamic> json, List<String> keys) {
  final String? value = _readString(json, keys);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required field: ${keys.join('/')}');
  }
  return value;
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value is String) {
      return value;
    }
  }
  return null;
}

bool? _readBool(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value is bool) {
      return value;
    }
  }
  return null;
}

num? _readNum(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value is num) {
      return value;
    }
  }
  return null;
}
