import '../../domain/entities/route_entity.dart';

// ─── Preview ──────────────────────────────────────────────────────────────────

class RoutePreviewRequest {
  const RoutePreviewRequest({
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    this.flexibilityMinutes = 15,
    this.waypoints = const <Map<String, double>>[],
  });

  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final int flexibilityMinutes;
  final List<Map<String, double>> waypoints;
}

class RoutePreviewDto {
  const RoutePreviewDto({
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final String polyline;
  final int distanceMeters;
  final int durationSeconds;

  factory RoutePreviewDto.fromJson(Map<String, dynamic> j) => RoutePreviewDto(
        polyline: _readRequiredString(j, <String>['polyline']),
        distanceMeters: _toInt(j['distance_meters']),
        durationSeconds: _toInt(j['duration_seconds']),
      );

  String get distanceLabel {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters} m';
  }

  String get durationLabel {
    final int mins = (durationSeconds / 60).round();
    if (mins >= 60) {
      return '${mins ~/ 60}h ${mins % 60}m';
    }
    return '${mins} min';
  }
}

// ─── Search result ────────────────────────────────────────────────────────────

class SearchResultDto {
  const SearchResultDto({
    required this.routeId,
    required this.driverId,
    required this.driverName,
    required this.driverRating,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehiclePlate,
    required this.walkingDistanceToPickup,
    required this.walkingTimeToPickup,
    required this.suggestedPickupLat,
    required this.suggestedPickupLng,
    required this.suggestedPickupName,
    required this.suggestedDropoffLat,
    required this.suggestedDropoffLng,
    required this.suggestedDropoffName,
    required this.walkingDistanceFromDropoff,
    required this.walkingTimeFromDropoff,
    required this.driverDepartureTime,
    required this.estimatedPickupTime,
    required this.availableSeats,
    required this.pricePerSeat,
    this.walkingPreferenceMeters = 1000,
    this.expandedWalkingLimitMeters = 1750,
    this.walkingExceedsPreference = false,
    this.walkingOverageMeters = 0,
    this.timeDifferenceMinutes = 0,
    this.timeExceedsPreference = false,
    this.timeOverageMinutes = 0,
    this.matchQuality = 'good',
    this.matchScore = 0,
    this.matchReasons = const <String>[],
  });

  final String routeId;
  final String driverId;
  final String? driverName;
  final double? driverRating;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlate;
  final int walkingDistanceToPickup;
  final int walkingTimeToPickup;
  final double? suggestedPickupLat;
  final double? suggestedPickupLng;
  final String? suggestedPickupName;
  final double? suggestedDropoffLat;
  final double? suggestedDropoffLng;
  final String? suggestedDropoffName;
  final int walkingDistanceFromDropoff;
  final int walkingTimeFromDropoff;
  final DateTime driverDepartureTime;
  final DateTime estimatedPickupTime;
  final int availableSeats;
  final int pricePerSeat;
  final int walkingPreferenceMeters;
  final int expandedWalkingLimitMeters;
  final bool walkingExceedsPreference;
  final int walkingOverageMeters;
  final int timeDifferenceMinutes;
  final bool timeExceedsPreference;
  final int timeOverageMinutes;
  final String matchQuality;
  final int matchScore;
  final List<String> matchReasons;

  factory SearchResultDto.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic>? pickupPt =
        j['suggested_pickup_point'] as Map<String, dynamic>?;
    final Map<String, dynamic>? dropoffPt =
        j['suggested_dropoff_point'] as Map<String, dynamic>?;
    return SearchResultDto(
      routeId: _readRequiredString(j, <String>['route_id', 'id']),
      driverId: _readRequiredString(j, <String>['driver_id']),
      driverName: _readString(j, <String>['driver_name']),
      driverRating: _toNullableDouble(j['driver_rating']),
      vehicleMake: _readString(j, <String>['vehicle_make']),
      vehicleModel: _readString(j, <String>['vehicle_model']),
      vehicleColor: _readString(j, <String>['vehicle_color']),
      vehiclePlate: _readString(j, <String>['vehicle_plate']),
      walkingDistanceToPickup: _toInt(j['walking_distance_to_pickup']),
      walkingTimeToPickup: _toInt(j['walking_time_to_pickup']),
      suggestedPickupLat: _toNullableDouble(pickupPt?['lat']),
      suggestedPickupLng: _toNullableDouble(pickupPt?['lng']),
      suggestedPickupName: _readString(
            pickupPt ?? <String, dynamic>{},
            <String>['name'],
          ) ??
          _readString(j, <String>['suggested_pickup_name']),
      suggestedDropoffLat: _toNullableDouble(dropoffPt?['lat']),
      suggestedDropoffLng: _toNullableDouble(dropoffPt?['lng']),
      suggestedDropoffName: _readString(
            dropoffPt ?? <String, dynamic>{},
            <String>['name'],
          ) ??
          _readString(j, <String>['suggested_dropoff_name']),
      walkingDistanceFromDropoff: _toInt(j['walking_distance_from_dropoff']),
      walkingTimeFromDropoff: _toInt(j['walking_time_from_dropoff']),
      driverDepartureTime: _parseDateTime(j['driver_departure_time']),
      estimatedPickupTime: _parseDateTime(j['estimated_pickup_time']),
      availableSeats: _toInt(j['available_seats']),
      pricePerSeat: _toInt(j['price_per_seat']),
      walkingPreferenceMeters: _toInt(
        j['walking_preference_meters'],
        fallback: 1000,
      ),
      expandedWalkingLimitMeters: _toInt(
        j['expanded_walking_limit_meters'],
        fallback: 1750,
      ),
      walkingExceedsPreference: j['walking_exceeds_preference'] == true,
      walkingOverageMeters: _toInt(j['walking_overage_meters']),
      timeDifferenceMinutes: _toInt(j['time_difference_minutes']),
      timeExceedsPreference: j['time_exceeds_preference'] == true,
      timeOverageMinutes: _toInt(j['time_overage_minutes']),
      matchQuality: _readString(j, <String>['match_quality']) ?? 'good',
      matchScore: _toInt(j['match_score']),
      matchReasons: (j['match_reasons'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(),
    );
  }

  String get walkingDistanceLabel {
    if (walkingDistanceToPickup >= 1000) {
      return '${(walkingDistanceToPickup / 1000).toStringAsFixed(1)} km walk';
    }
    return '${walkingDistanceToPickup} m walk';
  }

  String get finalWalkLabel {
    if (walkingDistanceFromDropoff >= 1000) {
      return '${(walkingDistanceFromDropoff / 1000).toStringAsFixed(1)} km final';
    }
    return '${walkingDistanceFromDropoff} m final';
  }

  String get matchQualityLabel {
    switch (matchQuality) {
      case 'best':
        return 'Best fit';
      case 'flexible':
        return 'More flexible';
      default:
        return 'Good fit';
    }
  }

  String get walkingTradeoffLabel {
    if (!walkingExceedsPreference || walkingOverageMeters <= 0) {
      return 'Within walk preference';
    }
    if (walkingOverageMeters >= 1000) {
      return '+${(walkingOverageMeters / 1000).toStringAsFixed(1)} km walk';
    }
    return '+${walkingOverageMeters} m walk';
  }

  String get timeTradeoffLabel {
    if (!timeExceedsPreference || timeOverageMinutes <= 0) {
      return '${timeDifferenceMinutes} min from request';
    }
    return '+${timeOverageMinutes} min time';
  }

  String get vehicleLabel {
    final String base =
        <String?>[vehicleMake, vehicleModel].whereType<String>().join(' ');
    if (vehiclePlate != null && base.isNotEmpty) return '$base · $vehiclePlate';
    if (vehiclePlate != null) return vehiclePlate!;
    return base;
  }
}

// ─── Route DTO ────────────────────────────────────────────────────────────────

class RouteDto {
  RouteDto({
    required this.routeId,
    required this.driverUserId,
    required this.driverName,
    required this.originName,
    required this.destinationName,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.departureDatetime,
    required this.pricePerSeatTzs,
    required this.totalSeats,
    required this.availableSeats,
    required this.vehicleModel,
    required this.vehiclePlate,
    required this.status,
    this.encodedPolyline,
    this.driverRating,
    this.estimatedArrivalDatetime,
    this.waypoints = const <RouteWaypointDto>[],
  });

  final String routeId;
  final String driverUserId;
  final String driverName;
  final String originName;
  final String destinationName;
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final DateTime departureDatetime;
  final int pricePerSeatTzs;
  final int totalSeats;
  final int availableSeats;
  final String vehicleModel;
  final String vehiclePlate;
  final String status;
  final String? encodedPolyline;
  final double? driverRating;
  final DateTime? estimatedArrivalDatetime;
  final List<RouteWaypointDto> waypoints;

  factory RouteDto.fromJson(Map<String, dynamic> j) {
    final int availableSeats = _toInt(
      j['available_seats'],
      fallback: 0,
    );
    final int bookedSeats = _toInt(
      j['booked_seats'],
      fallback: 0,
    );
    final int totalSeats = _toInt(
      j['total_seats'],
      fallback: availableSeats + bookedSeats,
    );

    return RouteDto(
      routeId: _readRequiredString(j, <String>['route_id', 'id']),
      driverUserId:
          _readRequiredString(j, <String>['driver_user_id', 'driver_id']),
      driverName: _readString(j, <String>['driver_name']) ?? '',
      originName: _readString(j, <String>['origin_name']) ?? 'Origin',
      destinationName:
          _readString(j, <String>['destination_name']) ?? 'Destination',
      originLat: _toDouble(j['origin_lat']),
      originLng: _toDouble(j['origin_lng']),
      destinationLat: _toDouble(j['destination_lat'] ?? j['dest_lat']),
      destinationLng: _toDouble(j['destination_lng'] ?? j['dest_lng']),
      departureDatetime: _parseDateTime(
        j['departure_datetime'] ?? j['departure_time'],
      ),
      pricePerSeatTzs: _toInt(
        j['price_per_seat_tzs'] ?? j['price_per_seat'],
      ),
      totalSeats: totalSeats,
      availableSeats: availableSeats,
      vehicleModel: _readString(j, <String>['vehicle_model']) ?? '',
      vehiclePlate: _readString(j, <String>['vehicle_plate']) ?? '',
      status: _readString(j, <String>['status']) ?? 'active',
      encodedPolyline: _readString(j, <String>['encoded_polyline', 'polyline']),
      driverRating: _toNullableDouble(j['driver_rating']),
      estimatedArrivalDatetime: j['estimated_arrival_datetime'] != null
          ? _parseDateTime(j['estimated_arrival_datetime'])
          : null,
      waypoints: (j['waypoints'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) =>
              RouteWaypointDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  RouteEntity toDomain() => RouteEntity(
        routeId: routeId,
        driverUserId: driverUserId,
        driverName: driverName,
        originName: originName,
        destinationName: destinationName,
        originLat: originLat,
        originLng: originLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        departureDatetime: departureDatetime,
        pricePerSeatTzs: pricePerSeatTzs,
        totalSeats: totalSeats,
        availableSeats: availableSeats,
        vehicleModel: vehicleModel,
        vehiclePlate: vehiclePlate,
        status: status,
        encodedPolyline: encodedPolyline,
        driverRating: driverRating,
        estimatedArrivalDatetime: estimatedArrivalDatetime,
        waypoints: waypoints.map((RouteWaypointDto w) => w.toDomain()).toList(),
      );
}

class RouteWaypointDto {
  const RouteWaypointDto({
    required this.name,
    required this.lat,
    required this.lng,
    required this.order,
  });

  final String name;
  final double lat;
  final double lng;
  final int order;

  factory RouteWaypointDto.fromJson(Map<String, dynamic> j) => RouteWaypointDto(
        name: _readString(j, <String>['name']) ?? '',
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        order: _toInt(j['order']),
      );

  RouteWaypoint toDomain() => RouteWaypoint(
        name: name,
        lat: lat,
        lng: lng,
        order: order,
      );
}

class RouteSearchParams {
  const RouteSearchParams({
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.desiredDepartureTime,
    this.timeFlexibilityMinutes = 30,
    this.maxWalkingDistanceMeters = 1000,
    this.seatsNeeded = 1,
    this.pickupLabel,
    this.dropoffLabel,
  });

  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final DateTime desiredDepartureTime;
  final int timeFlexibilityMinutes;
  final int maxWalkingDistanceMeters;
  final int seatsNeeded;
  final String? pickupLabel;
  final String? dropoffLabel;
}

class CreateRouteRequest {
  const CreateRouteRequest({
    required this.vehicleId,
    required this.originName,
    required this.originLat,
    required this.originLng,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    required this.availableSeats,
    required this.pricePerSeat,
    required this.departureTime,
    this.flexibilityMinutes = 15,
    this.waypoints = const <Map<String, double>>[],
    this.recurrence = 'none',
    this.recurrenceDays = const <int>[],
    this.recurrenceEndDate,
  });

  final String vehicleId;
  final String originName;
  final double originLat;
  final double originLng;
  final String destinationName;
  final double destinationLat;
  final double destinationLng;
  final int availableSeats;
  final int pricePerSeat;
  final DateTime departureTime;
  final int flexibilityMinutes;
  final List<Map<String, double>> waypoints;
  final String recurrence;
  final List<int> recurrenceDays;
  final DateTime? recurrenceEndDate;
}

class DriverVehicleOption {
  const DriverVehicleOption({
    required this.id,
    required this.make,
    required this.model,
    required this.plateNumber,
    this.color,
    this.year,
    this.capacity,
    this.isActive = false,
  });

  final String id;
  final String make;
  final String model;
  final String plateNumber;
  final String? color;
  final int? year;
  final int? capacity;
  final bool isActive;

  String get label {
    final String base = '$make $model'.trim();
    final String withYear = year != null && year! > 0 ? '$base ($year)' : base;
    final String normalized = withYear.trim().isEmpty ? 'Vehicle' : withYear;
    return '$normalized · $plateNumber';
  }

  factory DriverVehicleOption.fromJson(Map<String, dynamic> j) {
    return DriverVehicleOption(
      id: (j['id'] ?? j['vehicle_id']) as String,
      make: (j['make'] as String?) ?? '',
      model: (j['model'] as String?) ?? '',
      plateNumber:
          (j['plate_number'] ?? j['registration_number'] ?? '') as String,
      color: _readString(j, <String>['color', 'vehicle_color']),
      year: _toNullableInt(j['year']),
      capacity: _toNullableInt(j['capacity']),
      isActive: (j['is_active'] as bool?) ??
          (j['active'] as bool?) ??
          (j['is_active_vehicle'] as bool?) ??
          false,
    );
  }
}

String _readRequiredString(Map<String, dynamic> json, List<String> keys) {
  final String? value = _readString(json, keys);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required field: $keys');
  }
  return value;
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value == null) continue;
    if (value is String) return value;
    return value.toString();
  }
  return null;
}

DateTime _parseDateTime(dynamic value, {DateTime? fallback}) {
  if (value == null) return fallback ?? DateTime.now();
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return fallback ?? DateTime.now();
  }
}

double _toDouble(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _toInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return double.tryParse(value)?.round() ?? fallback;
  return fallback;
}

int? _toNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
