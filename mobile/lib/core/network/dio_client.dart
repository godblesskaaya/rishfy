import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/env.dart';
import '../constants/app_constants.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/retry_interceptor.dart';

/// Core Dio client used by all repositories.
/// Exposed via Riverpod — inject in your data sources.
final Provider<Dio> dioClientProvider = Provider<Dio>((Ref ref) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: AppConstants.apiConnectTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      sendTimeout: AppConstants.apiTimeout,
      contentType: 'application/json',
      responseType: ResponseType.json,
      headers: <String, String>{
        'Accept': 'application/json',
        'X-Client': 'rishfy-mobile',
        'X-Client-Version': '0.1.0',
      },
    ),
  );

  // Order matters: auth → retry → error → logger
  dio.interceptors.addAll(<Interceptor>[
    AuthInterceptor(ref),
    RetryInterceptor(dio),
    ErrorInterceptor(),
    if (Env.isDev)
      PrettyDioLogger(
        requestHeader: false,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: true,
        maxWidth: 100,
      ),
  ]);

  return dio;
});
