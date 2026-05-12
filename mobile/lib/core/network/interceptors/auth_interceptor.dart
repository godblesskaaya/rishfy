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

  // Avoid a refresh storm. When multiple requests fail with 401 at once,
  // one request refreshes and the rest await the same outcome.
  static bool _isRefreshing = false;
  static Future<bool>? _refreshFuture;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
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
    if (err.response?.statusCode != 401 ||
        _isPublicEndpoint(err.requestOptions.path)) {
      return handler.next(err);
    }

    if (err.requestOptions.path.contains('/auth/refresh-token')) {
      await _logout();
      return handler.next(err);
    }

    if (_isRefreshing) {
      final bool refreshed = await _waitForRefresh();
      if (!refreshed) {
        return handler.next(err);
      }

      try {
        final Response<dynamic> retried = await _retry(err.requestOptions);
        return handler.resolve(retried);
      } on DioException catch (retryErr) {
        return handler.next(retryErr);
      }
    }

    _isRefreshing = true;
    _refreshFuture = _performRefresh();

    try {
      final bool refreshed = await _refreshFuture!;

      if (!refreshed) {
        await _logout();
        return handler.next(err);
      }

      final Response<dynamic> retried = await _retry(err.requestOptions);
      return handler.resolve(retried);
    } catch (e, s) {
      AppLogger.error('Token refresh failed', error: e, stackTrace: s);
      await _logout();
      return handler.next(err);
    } finally {
      _isRefreshing = false;
      _refreshFuture = null;
    }
  }

  Future<bool> _performRefresh() {
    return _ref.read(authControllerProvider.notifier).refreshSession();
  }

  Future<bool> _waitForRefresh() async {
    final Future<bool>? refresh = _refreshFuture;
    if (refresh == null) {
      return false;
    }

    try {
      return await refresh;
    } catch (e, s) {
      AppLogger.error(
        'Waiting for token refresh failed',
        error: e,
        stackTrace: s,
      );
      return false;
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

  Future<void> _logout() async {
    await _ref.read(authControllerProvider.notifier).forceLogout();
  }

  bool _isPublicEndpoint(String path) {
    const List<String> publicPaths = <String>[
      '/api/v1/auth/login',
      '/api/v1/auth/register',
      '/api/v1/auth/verify-otp',
      '/api/v1/auth/resend-otp',
      '/api/v1/auth/reset-password',
      '/api/v1/auth/refresh-token',
    ];
    return publicPaths.any((String p) => path.contains(p));
  }
}
