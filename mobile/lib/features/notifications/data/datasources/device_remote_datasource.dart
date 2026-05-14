import 'package:dio/dio.dart';

import '../../../../core/network/interceptors/auth_interceptor.dart';

class DeviceRemoteDataSource {
  DeviceRemoteDataSource(this._dio);

  final Dio _dio;

  Future<void> registerToken({
    required String deviceId,
    required String fcmToken,
    required String platform,
    String? appVersion,
  }) async {
    await _dio.post<void>(
      '/api/v1/devices',
      options: Options(
        extra: const <String, dynamic>{kSkipAuthRefreshExtraKey: true},
      ),
      data: <String, dynamic>{
        'deviceId': deviceId,
        'fcmToken': fcmToken,
        'platform': platform,
        if (appVersion != null) 'appVersion': appVersion,
      },
    );
  }

  Future<void> refreshToken({
    required String deviceId,
    required String fcmToken,
  }) async {
    await _dio.patch<void>(
      '/api/v1/devices/$deviceId/token',
      options: Options(
        extra: const <String, dynamic>{kSkipAuthRefreshExtraKey: true},
      ),
      data: <String, dynamic>{'fcmToken': fcmToken},
    );
  }

  Future<void> unregister(String deviceId) async {
    await _dio.delete<void>('/api/v1/devices/$deviceId');
  }
}
