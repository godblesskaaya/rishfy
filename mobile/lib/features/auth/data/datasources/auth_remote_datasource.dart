import 'package:dio/dio.dart';

import '../../../../core/constants/app_logger.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/auth_models.dart';

/// Remote API calls to auth-service. Pure HTTP - no caching, no state.
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  static const String _basePath = '/api/v1/auth';

  Future<LoginResponseDto> login({
    required String identifier,
    required String password,
  }) {
    return _send<Map<String, dynamic>, LoginResponseDto>(
      operation: 'login',
      request: () => _dio.post<Map<String, dynamic>>(
        '$_basePath/login',
        data: <String, dynamic>{
          'identifier': identifier,
          'password': password,
        },
      ),
      parse: LoginResponseDto.fromJson,
    );
  }

  Future<RegistrationResponseDto> register({
    required String email,
    required String password,
    String? fullName,
    String? phoneNumber,
  }) {
    return _send<Map<String, dynamic>, RegistrationResponseDto>(
      operation: 'register',
      request: () => _dio.post<Map<String, dynamic>>(
        '$_basePath/register',
        data: <String, dynamic>{
          'email': email,
          'password': password,
          if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
          if (phoneNumber != null && phoneNumber.isNotEmpty) 'phoneNumber': phoneNumber,
        },
      ),
      parse: RegistrationResponseDto.fromJson,
    );
  }

  Future<LoginResponseDto> verifyOtp({
    required String userId,
    required String otpCode,
  }) {
    return _send<Map<String, dynamic>, LoginResponseDto>(
      operation: 'verifyOtp',
      request: () => _dio.post<Map<String, dynamic>>(
        '$_basePath/verify-otp',
        data: <String, dynamic>{
          'userId': userId,
          'otpCode': otpCode,
        },
      ),
      parse: LoginResponseDto.fromJson,
    );
  }

  /// Initiate password reset — backend issues an OTP to the user's contact.
  Future<void> requestPasswordReset({required String identifier}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_basePath/reset-password',
        data: <String, dynamic>{'identifier': identifier},
      );
    } on DioException catch (error) {
      final Object? mapped = error.error;
      if (mapped is AppException) throw mapped;
      rethrow;
    }
  }

  /// Confirm password reset with the OTP and a new password.
  Future<void> confirmPasswordReset({
    required String identifier,
    required String otpCode,
    required String newPassword,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_basePath/reset-password',
        data: <String, dynamic>{
          'identifier': identifier,
          'otpCode': otpCode,
          'newPassword': newPassword,
        },
      );
    } on DioException catch (error) {
      final Object? mapped = error.error;
      if (mapped is AppException) throw mapped;
      rethrow;
    }
  }

  /// Re-issue an OTP for the given user (register or reset-password purpose).
  Future<void> resendOtp({
    required String userId,
    String purpose = 'register',
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_basePath/resend-otp',
        data: <String, dynamic>{'userId': userId, 'purpose': purpose},
      );
    } on DioException catch (error) {
      final Object? mapped = error.error;
      if (mapped is AppException) throw mapped;
      rethrow;
    }
  }

  Future<RefreshResponseDto> refresh({
    required String refreshToken,
  }) {
    return _send<Map<String, dynamic>, RefreshResponseDto>(
      operation: 'refresh',
      request: () => _dio.post<Map<String, dynamic>>(
        '$_basePath/refresh-token',
        data: <String, dynamic>{'refreshToken': refreshToken},
      ),
      parse: RefreshResponseDto.fromJson,
    );
  }

  Future<void> logout({required String refreshToken}) async {
    try {
      await _dio.post<void>(
        '$_basePath/logout',
        data: <String, dynamic>{'refreshToken': refreshToken},
      );
    } on DioException catch (error, stackTrace) {
      final Object? mapped = error.error;
      if (mapped is AppException) {
        throw mapped;
      }

      AppLogger.warn(
        'Server logout failed',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error) {
      // Non-fatal - if server-side logout fails, we still clear local state.
      AppLogger.warn('Server logout failed: $error');
    }
  }

  Future<T> _send<R extends Object?, T>({
    required String operation,
    required Future<Response<R>> Function() request,
    required T Function(Map<String, dynamic> json) parse,
  }) async {
    try {
      final Response<R> response = await request();
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('Expected a JSON object response.');
      }

      try {
        return parse(data);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Unexpected auth response during $operation',
          error: error,
          stackTrace: stackTrace,
        );
        throw ServerException(
          message: 'Authentication service returned an unexpected response.',
          statusCode: response.statusCode ?? 500,
          code: 'AUTH_CONTRACT_MISMATCH',
        );
      }
    } on DioException catch (error, stackTrace) {
      final Object? mapped = error.error;
      if (mapped is AppException) {
        throw mapped;
      }

      AppLogger.error(
        'Auth request failed during $operation',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
