/// Base class for all app-level exceptions.
/// Repositories throw these; UI catches and shows localized messages.
sealed class AppException implements Exception {
  const AppException({
    required this.message,
    this.code,
  });

  final String message;
  final String? code;

  @override
  String toString() => '$runtimeType: $message${code != null ? ' ($code)' : ''}';
}

// ============================================================================
// Network-level errors
// ============================================================================

sealed class NetworkException extends AppException {
  const NetworkException({required super.message, super.code});

  const factory NetworkException.timeout() = _TimeoutException;
  const factory NetworkException.noConnection() = _NoConnectionException;
  const factory NetworkException.cancelled() = _CancelledException;
  const factory NetworkException.certificateError() = _CertificateException;
  const factory NetworkException.unknown(String msg) = _UnknownNetworkException;
}

class _TimeoutException extends NetworkException {
  const _TimeoutException()
      : super(message: 'Request timed out. Check your connection.');
}

class _NoConnectionException extends NetworkException {
  const _NoConnectionException()
      : super(message: 'No internet connection.');
}

class _CancelledException extends NetworkException {
  const _CancelledException() : super(message: 'Request cancelled.');
}

class _CertificateException extends NetworkException {
  const _CertificateException()
      : super(message: 'Secure connection could not be established.');
}

class _UnknownNetworkException extends NetworkException {
  const _UnknownNetworkException(String msg) : super(message: msg);
}

// ============================================================================
// Server-level errors (by HTTP status)
// ============================================================================

class ServerException extends AppException {
  const ServerException({
    required super.message,
    required this.statusCode,
    super.code,
  });

  final int statusCode;
}

class UnauthorizedException extends AppException {
  const UnauthorizedException({required super.message}) : super(code: 'UNAUTHORIZED');
}

class ForbiddenException extends AppException {
  const ForbiddenException({required super.message}) : super(code: 'FORBIDDEN');
}

class NotFoundException extends AppException {
  const NotFoundException({required super.message}) : super(code: 'NOT_FOUND');
}

class ConflictException extends AppException {
  const ConflictException({required super.message, super.code});
}

class ValidationException extends AppException {
  const ValidationException({
    required super.message,
    this.fieldErrors,
  }) : super(code: 'VALIDATION');

  final Map<String, dynamic>? fieldErrors;

  List<String> errorsFor(String field) {
    final dynamic value = fieldErrors?[field];
    if (value is List) {
      return value.map((dynamic e) => e.toString()).toList();
    }
    if (value is String) {
      return <String>[value];
    }
    return const <String>[];
  }
}

class RateLimitException extends AppException {
  const RateLimitException({required super.message})
      : super(code: 'RATE_LIMITED');
}

// ============================================================================
// Business logic errors
// ============================================================================

class BookingException extends AppException {
  const BookingException({required super.message, super.code});
}

class PaymentException extends AppException {
  const PaymentException({required super.message, super.code});
}

class LocationPermissionException extends AppException {
  const LocationPermissionException({required super.message})
      : super(code: 'LOCATION_PERMISSION_DENIED');
}
