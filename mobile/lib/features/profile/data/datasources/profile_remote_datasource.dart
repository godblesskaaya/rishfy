import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../../auth/data/models/auth_models.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../routes/data/models/route_models.dart';

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

  Future<DriverVehicleOption> setActiveVehicle(String vehicleId) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/api/v1/users/me/vehicles/$vehicleId/active',
    );
    return DriverVehicleOption.fromJson(_asMap(response.data));
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _dio.delete<void>('/api/v1/users/me/vehicles/$vehicleId');
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

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
