import 'dart:math';

import 'package:dio/dio.dart';

import '../../constants/app_constants.dart';
import '../../constants/app_logger.dart';

/// Retries transient failures (5xx, timeouts) with exponential backoff.
///
/// Never retries:
/// - Non-idempotent writes (POST/PUT/PATCH) unless they carry an Idempotency-Key
/// - Client errors (4xx except 429)
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio);

  final Dio _dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final int attempt = (err.requestOptions.extra['retry_attempt'] as int? ?? 0);

    if (!_shouldRetry(err, attempt)) {
      return handler.next(err);
    }

    final Duration delay = _backoff(attempt);
    AppLogger.warn(
      'Retrying ${err.requestOptions.path} '
      '(attempt ${attempt + 1}/${AppConstants.maxRetries}) '
      'after ${delay.inMilliseconds}ms',
    );

    await Future<void>.delayed(delay);

    try {
      err.requestOptions.extra['retry_attempt'] = attempt + 1;
      final Response<dynamic> response =
          await _dio.fetch<dynamic>(err.requestOptions);
      return handler.resolve(response);
    } on DioException catch (retriedErr) {
      return handler.next(retriedErr);
    }
  }

  bool _shouldRetry(DioException err, int attempt) {
    if (attempt >= AppConstants.maxRetries) {
      return false;
    }

    // Retry on network timeout / connection errors
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError) {
      return _isIdempotent(err.requestOptions);
    }

    // Retry on 5xx server errors
    final int? status = err.response?.statusCode;
    if (status != null && status >= 500 && status < 600) {
      return _isIdempotent(err.requestOptions);
    }

    // Retry on 429 (rate limited) regardless of method
    if (status == 429) {
      return true;
    }

    return false;
  }

  bool _isIdempotent(RequestOptions req) {
    const Set<String> idempotentMethods = <String>{'GET', 'HEAD', 'OPTIONS', 'DELETE', 'PUT'};
    if (idempotentMethods.contains(req.method.toUpperCase())) {
      return true;
    }
    // POST/PATCH are idempotent only if the caller supplied an idempotency key
    return req.headers.containsKey('Idempotency-Key');
  }

  Duration _backoff(int attempt) {
    // Exponential backoff with jitter: 500ms, 1s, 2s (+/- 20%)
    final int base = 500 * pow(2, attempt).toInt();
    final double jitter = Random().nextDouble() * 0.4 - 0.2; // -20% to +20%
    return Duration(milliseconds: (base * (1 + jitter)).round());
  }
}
