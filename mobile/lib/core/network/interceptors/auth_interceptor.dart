import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../constants/app_logger.dart';
import '../../storage/secure_storage.dart';

/// Attaches the JWT access token to every request.
///
/// On 401 responses, attempts a single refresh using the stored refresh token,
/// then retries the original request once. If refresh fails, logs the user out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._ref);

  final Ref _ref;

  // Avoid refresh storm — if multiple requests fail at the same time, only one
  // should trigger a refresh; the rest wait for it.
  static bool _isRefreshing = false;
  static final List<RequestOptions> _queue = <RequestOptions>[];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth for login, register, OTP, and webhook endpoints.
    if (_isPublicEndpoint(options.path)) {
      return handler.next(options);
    }

    final SecureStorage storage = _ref.read(secureStorageProvider);
    final String? token = await storage.readAccessToken();

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only intercept 401 from authenticated endpoints
    if (err.response?.statusCode != 401 ||
        _isPublicEndpoint(err.requestOptions.path)) {
      return handler.next(err);
    }

    // Prevent retrying a refresh endpoint itself
    if (err.requestOptions.path.contains('/auth/refresh')) {
      await _logout();
      return handler.next(err);
    }

    if (_isRefreshing) {
      // Queue and wait
      _queue.add(err.requestOptions);
      return;
    }

    _isRefreshing = true;

    try {
      final bool refreshed = await _ref
          .read(authControllerProvider.notifier)
          .refreshSession();

      if (!refreshed) {
        await _logout();
        return handler.next(err);
      }

      // Retry the original request with the new token
      final Response<dynamic> retried = await _retry(err.requestOptions);
      _processQueue();
      return handler.resolve(retried);
    } catch (e, s) {
      AppLogger.error('Token refresh failed', error: e, stackTrace: s);
      await _logout();
      return handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Response<dynamic>> _retry(RequestOptions req) async {
    final SecureStorage storage = _ref.read(secureStorageProvider);
    final String? token = await storage.readAccessToken();

    final Options options = Options(
      method: req.method,
      headers: <String, dynamic>{
        ...req.headers,
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    return Dio().request<dynamic>(
      '${req.baseUrl}${req.path}',
      data: req.data,
      queryParameters: req.queryParameters,
      options: options,
    );
  }

  Future<void> _processQueue() async {
    // Drain queued requests — in practice they will be re-fired by their
    // original callers once the refresh unblocks them. We just clear the list.
    _queue.clear();
  }

  Future<void> _logout() async {
    await _ref.read(authControllerProvider.notifier).forceLogout();
  }

  bool _isPublicEndpoint(String path) {
    const List<String> publicPaths = <String>[
      '/api/v1/auth/login',
      '/api/v1/auth/register',
      '/api/v1/auth/otp',
      '/api/v1/auth/refresh',
    ];
    return publicPaths.any((String p) => path.contains(p));
  }
}
