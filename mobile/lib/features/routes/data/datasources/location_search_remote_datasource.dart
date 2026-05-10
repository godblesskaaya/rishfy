import 'package:dio/dio.dart';

import '../../../../core/config/env.dart';

class LocationSearchResult {
  const LocationSearchResult({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.placeId,
  });

  final String label;
  final double latitude;
  final double longitude;
  final String? placeId;

  String get asLatLng =>
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
}

class LocationSearchRemoteDataSource {
  LocationSearchRemoteDataSource(this._dio);

  final Dio _dio;

  bool get isConfigured => Env.googleMapsApiKey.trim().isNotEmpty;

  Future<List<LocationSearchResult>> geocodeAddress(
    String query, {
    LocationSearchResult? proximity,
  }) async {
    if (!isConfigured || query.trim().isEmpty) {
      return const <LocationSearchResult>[];
    }

    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: <String, dynamic>{
        'address': query.trim(),
        'components': 'country:TZ',
        'region': 'tz',
        if (proximity != null)
          'bounds':
              '${(proximity.latitude - 0.3).toStringAsFixed(6)},${(proximity.longitude - 0.3).toStringAsFixed(6)}'
              '|'
              '${(proximity.latitude + 0.3).toStringAsFixed(6)},${(proximity.longitude + 0.3).toStringAsFixed(6)}',
        'key': Env.googleMapsApiKey,
      },
    );

    final List<dynamic> results =
        response.data?['results'] as List<dynamic>? ?? const <dynamic>[];

    return results
        .map((dynamic item) {
          if (item is! Map<String, dynamic>) return null;
          final Map<String, dynamic>? geometry =
              item['geometry'] as Map<String, dynamic>?;
          final Map<String, dynamic>? location =
              geometry?['location'] as Map<String, dynamic>?;
          final double? latitude = (location?['lat'] as num?)?.toDouble();
          final double? longitude = (location?['lng'] as num?)?.toDouble();
          if (latitude == null || longitude == null) return null;
          return LocationSearchResult(
            label: item['formatted_address'] as String? ?? query.trim(),
            latitude: latitude,
            longitude: longitude,
            placeId: item['place_id'] as String?,
          );
        })
        .whereType<LocationSearchResult>()
        .take(5)
        .toList();
  }

  Future<LocationSearchResult?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    if (!isConfigured) {
      return null;
    }

    final Response<Map<String, dynamic>> response =
        await _dio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: <String, dynamic>{
        'latlng':
            '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}',
        'result_type': 'street_address|route|premise|point_of_interest|locality',
        'key': Env.googleMapsApiKey,
      },
    );

    final List<dynamic> results =
        response.data?['results'] as List<dynamic>? ?? const <dynamic>[];
    if (results.isEmpty) {
      return LocationSearchResult(
        label:
            '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
        latitude: latitude,
        longitude: longitude,
      );
    }

    final Map<String, dynamic> top = results.first as Map<String, dynamic>;
    return LocationSearchResult(
      label: top['formatted_address'] as String? ??
          '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
      latitude: latitude,
      longitude: longitude,
      placeId: top['place_id'] as String?,
    );
  }
}
