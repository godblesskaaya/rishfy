import 'package:dio/dio.dart';

import '../models/route_models.dart';

class RouteRemoteDataSource {
  RouteRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<DriverVehicleOption>> listMyVehicles() async {
    final Response<dynamic> res =
        await _dio.get<dynamic>('/api/v1/users/me/vehicles');
    final dynamic payload = res.data;

    final List<dynamic> raw = payload is List<dynamic>
        ? payload
        : (payload is Map<String, dynamic> &&
                payload['vehicles'] is List<dynamic>)
            ? payload['vehicles'] as List<dynamic>
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

  Future<List<RouteDto>> searchRoutes(RouteSearchParams params) async {
    final _LatLng origin = _resolveLocation(params.origin);
    final _LatLng destination = _resolveLocation(params.destination);

    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/routes/search',
      queryParameters: <String, dynamic>{
        'origin_lat': origin.lat,
        'origin_lng': origin.lng,
        'destination_lat': destination.lat,
        'destination_lng': destination.lng,
        'departure_after': DateTime(
          params.departureDate.year,
          params.departureDate.month,
          params.departureDate.day,
        ).toIso8601String(),
        'seats_needed': params.seats,
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
    final dynamic payload = res.data?['route'] ?? res.data;
    return RouteDto.fromJson(payload as Map<String, dynamic>);
  }

  Future<RouteDto> createRoute(CreateRouteRequest req) async {
    final _LatLng origin = _resolveLocation(req.originName);
    final _LatLng destination = _resolveLocation(req.destinationName);

    final Response<Map<String, dynamic>> res =
        await _dio.post<Map<String, dynamic>>(
      '/api/v1/routes',
      data: <String, dynamic>{
        'vehicle_id': req.vehicleId,
        'origin_name': req.originName.trim(),
        'origin_lat': origin.lat,
        'origin_lng': origin.lng,
        'destination_name': req.destinationName.trim(),
        'destination_lat': destination.lat,
        'destination_lng': destination.lng,
        'available_seats': req.availableSeats,
        'price_per_seat': req.pricePerSeat,
        'departure_time': req.departureTime.toUtc().toIso8601String(),
        'recurrence': req.recurrence,
        if (req.recurrenceDays.isNotEmpty) 'recurrence_days': req.recurrenceDays,
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

class _LatLng {
  const _LatLng(this.lat, this.lng);

  final double lat;
  final double lng;
}

final Map<String, _LatLng> _knownLocations = <String, _LatLng>{
  'dar es salaam': _LatLng(-6.7924, 39.2083),
  'dodoma': _LatLng(-6.1630, 35.7516),
  'arusha': _LatLng(-3.3869, 36.6830),
  'moshi': _LatLng(-3.3349, 37.3404),
  'mwanza': _LatLng(-2.5164, 32.9175),
  'mbeya': _LatLng(-8.9094, 33.4607),
  'morogoro': _LatLng(-6.8235, 37.6611),
  'tanga': _LatLng(-5.0696, 39.0988),
  'zanzibar': _LatLng(-6.1659, 39.2026),
  'iringa': _LatLng(-7.7669, 35.6970),
  'tabora': _LatLng(-5.0200, 32.8000),
  'kigoma': _LatLng(-4.8762, 29.6267),
  'singida': _LatLng(-4.8163, 34.7436),
  'songea': _LatLng(-10.6833, 35.6500),
  'mtwara': _LatLng(-10.2667, 40.1833),
};

_LatLng _resolveLocation(String input) {
  final String normalized = input.trim().toLowerCase();

  final List<String> csvParts = normalized.split(',');
  if (csvParts.length == 2) {
    final double? lat = double.tryParse(csvParts[0].trim());
    final double? lng = double.tryParse(csvParts[1].trim());
    if (lat != null && lng != null) {
      return _LatLng(lat, lng);
    }
  }

  final _LatLng? mapped = _knownLocations[normalized];
  if (mapped != null) return mapped;

  throw const FormatException(
    'Location not recognized. Use "lat,lng" or a common city name in Tanzania.',
  );
}
