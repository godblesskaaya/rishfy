import 'package:dio/dio.dart';

import '../../errors/app_exception.dart';

/// Normalizes DioException into typed [AppException]s for the UI layer.
/// This runs last so the UI never sees raw Dio errors.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final AppException mapped = _map(err);

    final DioException wrapped = err.copyWith(
      error: mapped,
      message: mapped.message,
    );

    return handler.next(wrapped);
  }

  AppException _map(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException.timeout();

      case DioExceptionType.connectionError:
        return const NetworkException.noConnection();

      case DioExceptionType.cancel:
        return const NetworkException.cancelled();

      case DioExceptionType.badCertificate:
        return const NetworkException.certificateError();

      case DioExceptionType.badResponse:
        return _mapBadResponse(err);

      case DioExceptionType.unknown:
        return NetworkException.unknown(err.message ?? 'Unknown error');
    }
  }

  AppException _mapBadResponse(DioException err) {
    final int? status = err.response?.statusCode;
    final dynamic data = err.response?.data;

    // Try to extract server error structure: { error: "CODE", message: "...", metadata: {...} }
    String? code;
    String message = 'Something went wrong';
    Map<String, dynamic>? metadata;

    if (data is Map<String, dynamic>) {
      code = data['error'] as String?;
      message = data['message'] as String? ?? message;
      metadata = data['metadata'] as Map<String, dynamic>?;
    }

    switch (status) {
      case 400:
        return ValidationException(message: message, fieldErrors: metadata);
      case 401:
        return UnauthorizedException(message: message);
      case 403:
        return ForbiddenException(message: message);
      case 404:
        return NotFoundException(message: message);
      case 409:
        return ConflictException(message: message, code: code);
      case 422:
        return ValidationException(message: message, fieldErrors: metadata);
      case 429:
        return RateLimitException(message: message);
      case 500:
      case 502:
      case 503:
      case 504:
        return ServerException(message: message, statusCode: status);
      default:
        return ServerException(
          message: message,
          statusCode: status ?? 0,
          code: code,
        );
    }
  }
}
