import 'package:dio/dio.dart';

import '../models/route_models.dart';

class RouteRemoteDataSource {
  RouteRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<RouteDto>> searchRoutes(RouteSearchParams params) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/routes/search',
      queryParameters: <String, dynamic>{
        'origin': params.origin,
        'destination': params.destination,
        'departure_date':
            params.departureDate.toIso8601String().substring(0, 10),
        'seats': params.seats,
      },
    );
    final List<dynamic> data =
        res.data?['routes'] as List<dynamic>? ?? <dynamic>[];
    return data
        .map((dynamic e) => RouteDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RouteDto> getRoute(String routeId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>('/api/v1/routes/$routeId');
    return RouteDto.fromJson(res.data!['route'] as Map<String, dynamic>);
  }
}
