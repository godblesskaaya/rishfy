import 'package:dio/dio.dart';

import '../models/route_models.dart';

class RouteRemoteDataSource {
  RouteRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<RouteDto>> listMyRoutes() async {
    try {
      final Response<dynamic> res =
          await _dio.get<dynamic>('/api/v1/routes/me');
      return _parseRouteList(res.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return const <RouteDto>[];
      }
      rethrow;
    }
  }

  Future<void> cancelRoute(String routeId) async {
    await _dio.delete<void>('/api/v1/routes/$routeId');
  }

  List<RouteDto> _parseRouteList(dynamic payload) {
    final List<dynamic> raw = payload is List<dynamic>
        ? payload
        : (payload is Map<String, dynamic> &&
                payload['routes'] is List<dynamic>)
            ? payload['routes'] as List<dynamic>
            : <dynamic>[];

    return raw
        .map((dynamic item) {
          if (item is Map<String, dynamic>) return item;
          if (item is Map) return Map<String, dynamic>.from(item);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .map(RouteDto.fromJson)
        .toList();
  }

  Future<List<DriverVehicleOption>> listMyVehicles() async {
    final Response<dynamic> res =
        await _dio.get<dynamic>('/api/v1/users/me/vehicles');
    final dynamic payload = res.data;

    final List<dynamic> raw = payload is List<dynamic>
        ? payload
        : (payload is Map<String, dynamic> &&
                payload['vehicles'] is List<dynamic>)
            ? payload['vehicles'] as List<dynamic>
            : (payload is Map<String, dynamic> &&
                    payload['data'] is List<dynamic>)
                ? payload['data'] as List<dynamic>
                : <dynamic>[];

    return raw
        .map((dynamic item) {
          if (item is Map<String, dynamic>) return item;
          if (item is Map) return Map<String, dynamic>.from(item);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .map(DriverVehicleOption.fromJson)
        .toList();
  }

  Future<List<SearchResultDto>> searchRoutes(RouteSearchParams params) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/routes/search',
      queryParameters: <String, dynamic>{
        'pickup_lat': params.pickupLat,
        'pickup_lng': params.pickupLng,
        'dropoff_lat': params.dropoffLat,
        'dropoff_lng': params.dropoffLng,
        'desired_departure_time':
            params.desiredDepartureTime.toUtc().toIso8601String(),
        'time_flexibility_minutes': params.timeFlexibilityMinutes,
        'max_walking_distance': params.maxWalkingDistanceMeters,
        'seats_needed': params.seatsNeeded,
      },
    );
    final List<dynamic> data =
        res.data?['routes'] as List<dynamic>? ?? <dynamic>[];
    return data
        .map((dynamic e) => SearchResultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RoutePreviewDto> previewRoute(RoutePreviewRequest req) async {
    final Response<Map<String, dynamic>> res =
        await _dio.post<Map<String, dynamic>>(
      '/api/v1/routes/preview',
      data: <String, dynamic>{
        'origin_lat': req.originLat,
        'origin_lng': req.originLng,
        'destination_lat': req.destinationLat,
        'destination_lng': req.destinationLng,
        if (req.waypoints.isNotEmpty) 'waypoints': req.waypoints,
      },
    );
    return RoutePreviewDto.fromJson(res.data!);
  }

  Future<RouteDto> getRoute(String routeId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>('/api/v1/routes/$routeId');
    final dynamic payload = res.data?['route'] ?? res.data;
    return RouteDto.fromJson(payload as Map<String, dynamic>);
  }

  Future<RouteDto> createRoute(CreateRouteRequest req) async {
    final Response<Map<String, dynamic>> res =
        await _dio.post<Map<String, dynamic>>(
      '/api/v1/routes',
      data: <String, dynamic>{
        'vehicle_id': req.vehicleId,
        'origin_name': req.originName.trim(),
        'origin_lat': req.originLat,
        'origin_lng': req.originLng,
        'destination_name': req.destinationName.trim(),
        'destination_lat': req.destinationLat,
        'destination_lng': req.destinationLng,
        'available_seats': req.availableSeats,
        'price_per_seat': req.pricePerSeat,
        'departure_time': req.departureTime.toUtc().toIso8601String(),
        'flexibility_minutes': req.flexibilityMinutes,
        if (req.waypoints.isNotEmpty) 'waypoints': req.waypoints,
        'recurrence': req.recurrence,
        if (req.recurrenceDays.isNotEmpty)
          'recurrence_days': req.recurrenceDays,
        if (req.recurrenceEndDate != null)
          'recurrence_end_date':
              '${req.recurrenceEndDate!.year.toString().padLeft(4, '0')}-'
                  '${req.recurrenceEndDate!.month.toString().padLeft(2, '0')}-'
                  '${req.recurrenceEndDate!.day.toString().padLeft(2, '0')}',
      },
    );
    final dynamic payload = res.data?['route'] ?? res.data;
    return RouteDto.fromJson(payload as Map<String, dynamic>);
  }
}
