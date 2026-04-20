import 'package:equatable/equatable.dart';

/// User roles supported by the app.
enum UserRole {
  passenger,
  driver,
  admin,
  support;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (UserRole r) => r.name == value.toLowerCase(),
      orElse: () => UserRole.passenger,
    );
  }
}

class User extends Equatable {
  const User({
    required this.userId,
    required this.phoneNumber,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isVerified,
    this.email,
    this.profilePictureUrl,
    this.ratingAverage = 0.0,
    this.ratingCount = 0,
    this.language = 'en',
  });

  final String userId;
  final String phoneNumber;
  final String firstName;
  final String lastName;
  final String? email;
  final String? profilePictureUrl;
  final UserRole role;
  final bool isVerified;
  final double ratingAverage;
  final int ratingCount;
  final String language;

  String get fullName => '$firstName $lastName';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}';

  /// True if user is both passenger and driver (can switch roles).
  bool get canSwitchRoles => role == UserRole.driver;

  User copyWith({
    String? userId,
    String? phoneNumber,
    String? firstName,
    String? lastName,
    String? email,
    String? profilePictureUrl,
    UserRole? role,
    bool? isVerified,
    double? ratingAverage,
    int? ratingCount,
    String? language,
  }) {
    return User(
      userId: userId ?? this.userId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      ratingAverage: ratingAverage ?? this.ratingAverage,
      ratingCount: ratingCount ?? this.ratingCount,
      language: language ?? this.language,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        userId,
        phoneNumber,
        firstName,
        lastName,
        email,
        profilePictureUrl,
        role,
        isVerified,
        ratingAverage,
        ratingCount,
        language,
      ];
}

/// Authentication session — tokens + expiry.
class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final User user;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Refresh if less than 2 minutes left.
  bool get shouldRefresh =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  @override
  List<Object?> get props =>
      <Object?>[accessToken, refreshToken, expiresAt, user];
}
