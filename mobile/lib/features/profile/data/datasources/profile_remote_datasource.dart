import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../auth/data/models/auth_models.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../routes/data/models/route_models.dart';
import '../../domain/blocked_user.dart';
import '../../domain/emergency_contact.dart';
import '../../domain/favorite_driver.dart';
import '../../domain/payment_method.dart';
import '../../domain/public_driver_profile.dart';
import '../../domain/support_case.dart';

final Provider<ProfileRemoteDataSource> profileRemoteDataSourceProvider =
    Provider<ProfileRemoteDataSource>(
  (Ref ref) => ProfileRemoteDataSource(ref.read(dioClientProvider)),
);

class BecomeDriverRequest {
  const BecomeDriverRequest({
    required this.licenseNumber,
    required this.licenseExpiry,
    this.latraPermitNumber,
  });

  final String licenseNumber;
  final DateTime licenseExpiry;
  final String? latraPermitNumber;
}

class CreateVehicleRequest {
  const CreateVehicleRequest({
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    required this.plateNumber,
    required this.capacity,
  });

  final String make;
  final String model;
  final int year;
  final String color;
  final String plateNumber;
  final int capacity;
}

class ProfileRemoteDataSource {
  ProfileRemoteDataSource(this._dio);

  final Dio _dio;

  Future<User> getCurrentUser() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/v1/users/me');
    final Map<String, dynamic> payload = _asMap(response.data);
    return UserDto.fromJson(payload['data'] as Map<String, dynamic>? ?? payload)
        .toDomain();
  }

  Future<User> updateProfile({String? fullName, String? email}) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (fullName != null && fullName.trim().isNotEmpty)
        'full_name': fullName.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    if (body.isEmpty) {
      return getCurrentUser();
    }
    final Response<dynamic> response =
        await _dio.patch<dynamic>('/api/v1/users/me', data: body);
    final Map<String, dynamic> payload = _asMap(response.data);
    return UserDto.fromJson(payload['data'] as Map<String, dynamic>? ?? payload)
        .toDomain();
  }

  Future<User> becomeDriver(BecomeDriverRequest request) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/v1/users/me/become-driver',
      data: <String, dynamic>{
        'license_number': request.licenseNumber.trim(),
        'license_expiry': _formatDate(request.licenseExpiry),
        if (request.latraPermitNumber != null &&
            request.latraPermitNumber!.trim().isNotEmpty)
          'latra_permit_number': request.latraPermitNumber!.trim(),
      },
    );
    final Map<String, dynamic> payload = _asMap(response.data);
    final Map<String, dynamic>? userJson = payload['user'] as Map<String, dynamic>?;
    if (userJson != null) {
      return UserDto.fromJson(userJson).toDomain();
    }
    return getCurrentUser();
  }

  Future<List<DriverVehicleOption>> listMyVehicles() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/v1/users/me/vehicles');
    final dynamic payload = response.data;
    final List<dynamic> raw = payload is List<dynamic>
        ? payload
        : (payload is Map<String, dynamic> &&
                payload['vehicles'] is List<dynamic>)
            ? payload['vehicles'] as List<dynamic>
            : <dynamic>[];

    return raw
        .map((dynamic item) {
          if (item is Map<String, dynamic>) return item;
          if (item is Map) return Map<String, dynamic>.from(item);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .map(DriverVehicleOption.fromJson)
        .toList();
  }

  Future<DriverVehicleOption> addVehicle(CreateVehicleRequest request) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/v1/users/me/vehicles',
      data: <String, dynamic>{
        'make': request.make.trim(),
        'model': request.model.trim(),
        'year': request.year,
        'color': request.color.trim(),
        'plate_number': request.plateNumber.trim().toUpperCase(),
        'capacity': request.capacity,
      },
    );
    return DriverVehicleOption.fromJson(_asMap(response.data));
  }

  Future<DriverVehicleOption> updateVehicle(
    String vehicleId,
    CreateVehicleRequest request,
  ) async {
    final Response<dynamic> response = await _dio.patch<dynamic>(
      '/api/v1/users/me/vehicles/$vehicleId',
      data: <String, dynamic>{
        'make': request.make.trim(),
        'model': request.model.trim(),
        'year': request.year,
        'color': request.color.trim(),
        'plate_number': request.plateNumber.trim().toUpperCase(),
        'capacity': request.capacity,
      },
    );
    return DriverVehicleOption.fromJson(_asMap(response.data));
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _dio.delete<void>('/api/v1/users/me/vehicles/$vehicleId');
  }

  Future<void> setActiveVehicle(String vehicleId) async {
    await _dio.put<void>(
      '/api/v1/users/me/vehicles/$vehicleId/active',
    );
  }

  Future<List<PaymentMethod>> listPaymentMethods() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/v1/users/me/payment-methods');
    final Map<String, dynamic> payload = _asMap(response.data);
    final List<dynamic> raw = payload['methods'] is List<dynamic>
        ? payload['methods'] as List<dynamic>
        : <dynamic>[];
    return raw
        .map((dynamic item) => PaymentMethod.fromJson(_asMap(item)))
        .toList();
  }

  Future<PaymentMethod> addPaymentMethod({
    required String label,
    required String provider,
    required String phone,
    bool isDefault = false,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/v1/users/me/payment-methods',
      data: <String, dynamic>{
        'label': label.trim(),
        'provider': provider.trim(),
        'phone': phone.trim(),
        'isDefault': isDefault,
      },
    );
    return PaymentMethod.fromJson(_asMap(response.data));
  }

  Future<PaymentMethod> updatePaymentMethod(PaymentMethod method) async {
    final Response<dynamic> response = await _dio.patch<dynamic>(
      '/api/v1/users/me/payment-methods/${method.id}',
      data: <String, dynamic>{
        'label': method.label.trim(),
        'provider': method.provider.trim(),
        'phone': method.phone.trim(),
        'isDefault': method.isDefault,
      },
    );
    return PaymentMethod.fromJson(_asMap(response.data));
  }

  Future<void> deletePaymentMethod(String methodId) async {
    await _dio.delete<void>('/api/v1/users/me/payment-methods/$methodId');
  }

  Future<List<EmergencyContact>> listEmergencyContacts() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/v1/users/me/emergency-contacts');
    final Map<String, dynamic> payload = _asMap(response.data);
    final List<dynamic> raw = payload['contacts'] is List<dynamic>
        ? payload['contacts'] as List<dynamic>
        : <dynamic>[];
    return raw
        .map((dynamic item) => EmergencyContact.fromJson(_asMap(item)))
        .toList();
  }

  Future<EmergencyContact> addEmergencyContact({
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/v1/users/me/emergency-contacts',
      data: <String, dynamic>{
        'name': name.trim(),
        'phone': phone.trim(),
        if (relationship != null && relationship.trim().isNotEmpty)
          'relationship': relationship.trim(),
      },
    );
    return EmergencyContact.fromJson(_asMap(response.data));
  }

  Future<EmergencyContact> updateEmergencyContact(
    EmergencyContact contact,
  ) async {
    final Response<dynamic> response = await _dio.patch<dynamic>(
      '/api/v1/users/me/emergency-contacts/${contact.id}',
      data: <String, dynamic>{
        'name': contact.name.trim(),
        'phone': contact.phone.trim(),
        if (contact.relationship != null &&
            contact.relationship!.trim().isNotEmpty)
          'relationship': contact.relationship!.trim(),
      },
    );
    return EmergencyContact.fromJson(_asMap(response.data));
  }

  Future<void> deleteEmergencyContact(String contactId) async {
    await _dio.delete<void>('/api/v1/users/me/emergency-contacts/$contactId');
  }

  Future<User> confirmProfilePictureUrl(String publicUrl) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/v1/users/me/profile-picture/confirm',
      data: <String, dynamic>{'public_url': publicUrl.trim()},
    );
    final Map<String, dynamic> payload = _asMap(response.data);
    return UserDto.fromJson(payload['data'] as Map<String, dynamic>? ?? payload)
        .toDomain();
  }

  Future<List<FavoriteDriver>> listFavoriteDrivers() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/v1/users/me/favorite-drivers');
    final Map<String, dynamic> payload = _asMap(response.data);
    final List<dynamic> raw = payload['favorites'] is List<dynamic>
        ? payload['favorites'] as List<dynamic>
        : <dynamic>[];

    final List<FavoriteDriver> favorites = <FavoriteDriver>[];
    for (final dynamic item in raw) {
      final Map<String, dynamic> row = _asMap(item);
      final String driverUserId = _readString(
            row,
            <String>['driver_user_id', 'driverUserId'],
          ) ??
          '';
      if (driverUserId.isEmpty) continue;
      favorites.add(
        FavoriteDriver(
          id: _readString(row, <String>['id']) ?? driverUserId,
          driverUserId: driverUserId,
          createdAt: _readDateTime(row, <String>['created_at', 'createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          driver: _userFromFavoriteRow(row),
	        ),
	      );
	    }
    return favorites;
  }

  Future<void> addFavoriteDriver(String driverUserId) async {
    await _dio.post<void>('/api/v1/users/me/favorite-drivers/$driverUserId');
  }

  Future<void> removeFavoriteDriver(String driverUserId) async {
    await _dio.delete<void>('/api/v1/users/me/favorite-drivers/$driverUserId');
  }

  Future<List<BlockedUser>> listBlockedUsers() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/v1/users/me/blocks');
    final Map<String, dynamic> payload = _asMap(response.data);
    final List<dynamic> raw = payload['blocks'] is List<dynamic>
        ? payload['blocks'] as List<dynamic>
        : <dynamic>[];

    return raw.map((dynamic item) {
      final Map<String, dynamic> row = _asMap(item);
      final String blockedUserId = _readString(
            row,
            <String>['blocked_id', 'blockedId', 'blocked_user_id'],
          ) ??
          '';
      return BlockedUser(
        id: _readString(row, <String>['id']) ?? blockedUserId,
        blockedUserId: blockedUserId,
        displayNameOverride: _readString(
          row,
          <String>['blocked_full_name', 'blockedFullName', 'displayName'],
        ),
        role: _readString(row, <String>['blocked_role', 'blockedRole']),
        ratingAverage: _readDouble(
          row,
          <String>['blocked_average_rating', 'blockedAverageRating'],
        ),
        ratingCount: _readIntOrNull(
          row,
          <String>['blocked_total_ratings', 'blockedTotalRatings'],
        ),
        reason: _readString(row, <String>['reason']),
        createdAt: _readDateTime(row, <String>['created_at', 'createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    }).where((BlockedUser block) => block.blockedUserId.isNotEmpty).toList();
  }

  Future<void> blockUser(String userId, {String? reason}) async {
    await _dio.post<void>(
      '/api/v1/users/me/blocks/$userId',
      data: <String, dynamic>{
        if (reason != null && reason.trim().isNotEmpty)
          'reason': reason.trim(),
      },
    );
  }

  Future<void> unblockUser(String userId) async {
    await _dio.delete<void>('/api/v1/users/me/blocks/$userId');
  }

  Future<PublicDriverProfile> getPublicDriver(String driverUserId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/v1/users/drivers/$driverUserId');
    final Map<String, dynamic> payload = _asMap(response.data);
    final dynamic userJson = payload['user'];
    late final User user;
    if (userJson is Map<String, dynamic>) {
      user = UserDto.fromJson(userJson).toDomain();
    } else if (userJson is Map) {
      user = UserDto.fromJson(Map<String, dynamic>.from(userJson)).toDomain();
    } else {
      throw const FormatException('Expected public driver profile response.');
    }

    final Map<String, dynamic>? driverProfileJson = payload['driverProfile'] is Map
        ? _asMap(payload['driverProfile'])
        : null;
    final List<DriverVehicleOption> vehicles = (payload['vehicles'] as List<dynamic>? ??
            <dynamic>[])
        .map((dynamic item) => DriverVehicleOption.fromJson(_asMap(item)))
        .toList();
    final DriverVehicleOption? activeVehicle = payload['activeVehicle'] is Map
        ? DriverVehicleOption.fromJson(_asMap(payload['activeVehicle']))
        : _firstActiveVehicle(vehicles);
    final List<DriverReview> reviews = (payload['reviews'] as List<dynamic>? ??
            <dynamic>[])
        .map((dynamic item) {
          final Map<String, dynamic> row = _asMap(item);
          return DriverReview(
            ratingId: _readString(row, <String>['id', 'ratingId']) ?? '',
            score: _readIntOrNull(row, <String>['score']) ?? 0,
            comment: _readString(row, <String>['comment']),
            createdAt: _readDateTime(row, <String>['created_at', 'createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0),
          );
        })
        .toList();

    return PublicDriverProfile(
      user: user,
      driverProfile: driverProfileJson == null
          ? null
          : DriverProfileSummary(
              isVerified: (driverProfileJson['is_verified'] as bool?) ??
                  (driverProfileJson['isVerified'] as bool?) ??
                  false,
              licenseExpiry: _readDateTime(
                driverProfileJson,
                <String>['license_expiry', 'licenseExpiry'],
              ),
              verifiedAt: _readDateTime(
                driverProfileJson,
                <String>['verified_at', 'verifiedAt'],
              ),
              latraPermitNumber: _readString(
                driverProfileJson,
                <String>['latra_permit_number', 'latraPermitNumber'],
              ),
            ),
      activeVehicle: activeVehicle,
      vehicles: vehicles,
      reviews: reviews,
    );
  }

  Future<List<SupportCase>> listSupportCases() async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/v1/users/me/support-cases');
    final Map<String, dynamic> payload = _asMap(response.data);
    final List<dynamic> raw = payload['cases'] is List<dynamic>
        ? payload['cases'] as List<dynamic>
        : <dynamic>[];
    return raw
        .map((dynamic item) => SupportCase.fromJson(_asMap(item)))
        .toList();
  }

  Future<SupportCase> createSupportCase({
    required String subject,
    required String message,
    required String category,
    String? bookingId,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/v1/users/me/support-cases',
      data: <String, dynamic>{
        'subject': subject.trim(),
        'message': message.trim(),
        'category': category.trim(),
        if (bookingId != null && bookingId.trim().isNotEmpty)
          'bookingId': bookingId.trim(),
      },
    );
    return SupportCase.fromJson(_asMap(response.data));
  }

  DriverVehicleOption? _firstActiveVehicle(List<DriverVehicleOption> vehicles) {
    for (final DriverVehicleOption vehicle in vehicles) {
      if (vehicle.isActive) return vehicle;
    }
    return vehicles.isEmpty ? null : vehicles.first;
  }

  User? _userFromFavoriteRow(Map<String, dynamic> row) {
    final String? fullName = _readString(
      row,
      <String>['driver_full_name', 'driverFullName'],
    );
    if (fullName == null || fullName.isEmpty) return null;
    return UserDto.fromJson(<String, dynamic>{
      'id': _readString(row, <String>['driver_user_id', 'driverUserId']),
      'full_name': fullName,
      'role': 'driver',
      'average_rating': _readString(
        row,
        <String>['driver_average_rating', 'driverAverageRating'],
      ),
      'total_ratings': _readIntOrNull(
        row,
        <String>['driver_total_ratings', 'driverTotalRatings'],
      ),
      'profile_picture_url': _readString(
        row,
        <String>['driver_profile_picture_url', 'driverProfilePictureUrl'],
      ),
      'is_verified': true,
    }).toDomain();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw const FormatException('Expected JSON object response.');
  }

  String? _readString(Map<String, dynamic> json, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  DateTime? _readDateTime(Map<String, dynamic> json, List<String> keys) {
    final String? value = _readString(json, keys);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  double? _readDouble(Map<String, dynamic> json, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
    }
    return null;
  }

  int? _readIntOrNull(Map<String, dynamic> json, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = json[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value);
    }
    return null;
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
