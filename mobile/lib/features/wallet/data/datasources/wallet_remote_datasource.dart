import 'package:dio/dio.dart';

import '../models/wallet_models.dart';

class WalletRemoteDataSource {
  WalletRemoteDataSource(this._dio);

  final Dio _dio;

  Future<DriverEarningsStats> getDriverEarnings(String driverId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/drivers/$driverId/earnings',
    );
    return DriverEarningsStats.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<List<DriverPayout>> listDriverPayouts(String driverId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/drivers/$driverId/payouts',
      queryParameters: <String, dynamic>{'page': 1, 'page_size': 50},
    );
    final List<dynamic> items =
        res.data?['items'] as List<dynamic>? ?? <dynamic>[];
    return items
        .map((dynamic item) =>
            DriverPayout.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DriverPayoutDetail> getDriverPayoutDetail({
    required String driverId,
    required String payoutId,
  }) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/drivers/$driverId/payouts/$payoutId',
    );
    return DriverPayoutDetail.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<DriverPayout> requestDriverPayout({
    required String driverId,
    required String payoutMethod,
    required String payoutPhone,
  }) async {
    final Response<Map<String, dynamic>> res =
        await _dio.post<Map<String, dynamic>>(
      '/api/v1/drivers/$driverId/settlements',
      data: <String, dynamic>{
        'payoutMethod': payoutMethod,
        'payoutPhone': payoutPhone,
      },
    );
    return DriverPayout.fromJson(res.data ?? <String, dynamic>{});
  }
}
