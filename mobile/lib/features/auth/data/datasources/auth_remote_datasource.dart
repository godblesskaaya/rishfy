import 'package:dio/dio.dart';

import '../../../../core/constants/app_logger.dart';
import '../models/auth_models.dart';

/// Remote API calls to auth-service. Pure HTTP — no caching, no state.
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  static const String _basePath = '/api/v1/auth';

  Future<OtpRequestResponseDto> requestOtp({
    required String phoneNumber,
    required String purpose,
    String locale = 'en',
  }) async {
    final Response<Map<String, dynamic>> response =
        await _dio.post<Map<String, dynamic>>(
      '$_basePath/otp/request',
      data: <String, dynamic>{
        'phone_number': phoneNumber,
        'purpose': purpose,
        'locale': locale,
      },
    );
    return OtpRequestResponseDto.fromJson(response.data!);
  }

  Future<LoginResponseDto> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    required String otpReference,
    required String deviceId,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _dio.post<Map<String, dynamic>>(
      '$_basePath/otp/verify',
      data: <String, dynamic>{
        'phone_number': phoneNumber,
        'otp_code': otpCode,
        'otp_reference': otpReference,
        'device_id': deviceId,
      },
    );
    return LoginResponseDto.fromJson(response.data!);
  }

  Future<LoginResponseDto> register({
    required String phoneNumber,
    required String firstName,
    required String lastName,
    required String otpCode,
    required String otpReference,
    required String deviceId,
    String? email,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _dio.post<Map<String, dynamic>>(
      '$_basePath/register',
      data: <String, dynamic>{
        'phone_number': phoneNumber,
        'first_name': firstName,
        'last_name': lastName,
        'otp_code': otpCode,
        'otp_reference': otpReference,
        'device_id': deviceId,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
    return LoginResponseDto.fromJson(response.data!);
  }

  Future<AuthTokensDto> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _dio.post<Map<String, dynamic>>(
      '$_basePath/refresh',
      data: <String, dynamic>{
        'refresh_token': refreshToken,
        'device_id': deviceId,
      },
    );
    return AuthTokensDto.fromJson(response.data!);
  }

  Future<void> logout({required String refreshToken}) async {
    try {
      await _dio.post<void>(
        '$_basePath/logout',
        data: <String, dynamic>{'refresh_token': refreshToken},
      );
    } catch (e) {
      // Non-fatal — if server-side logout fails, we still clear local state.
      AppLogger.warn('Server logout failed: $e');
    }
  }

  Future<bool> checkPhoneExists(String phoneNumber) async {
    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>(
      '$_basePath/phone/check',
      queryParameters: <String, dynamic>{'phone_number': phoneNumber},
    );
    return response.data?['exists'] as bool? ?? false;
  }
}
