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
        polyline: j['polyline'] as String,
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
    required this.walkingDistanceFromDropoff,
    required this.walkingTimeFromDropoff,
    required this.driverDepartureTime,
    required this.estimatedPickupTime,
    required this.availableSeats,
    required this.pricePerSeat,
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
  final double suggestedPickupLat;
  final double suggestedPickupLng;
  final String? suggestedPickupName;
  final int walkingDistanceFromDropoff;
  final int walkingTimeFromDropoff;
  final DateTime driverDepartureTime;
  final DateTime estimatedPickupTime;
  final int availableSeats;
  final int pricePerSeat;

  factory SearchResultDto.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic>? pickupPt =
        j['suggested_pickup_point'] as Map<String, dynamic>?;
    return SearchResultDto(
      routeId: j['route_id'] as String,
      driverId: j['driver_id'] as String,
      driverName: j['driver_name'] as String?,
      driverRating: (j['driver_rating'] as num?)?.toDouble(),
      vehicleMake: j['vehicle_make'] as String?,
      vehicleModel: j['vehicle_model'] as String?,
      vehicleColor: j['vehicle_color'] as String?,
      vehiclePlate: j['vehicle_plate'] as String?,
      walkingDistanceToPickup: _toInt(j['walking_distance_to_pickup']),
      walkingTimeToPickup: _toInt(j['walking_time_to_pickup']),
      suggestedPickupLat: (pickupPt?['lat'] as num?)?.toDouble() ?? 0.0,
      suggestedPickupLng: (pickupPt?['lng'] as num?)?.toDouble() ?? 0.0,
      suggestedPickupName: pickupPt?['name'] as String?,
      walkingDistanceFromDropoff: _toInt(j['walking_distance_from_dropoff']),
      walkingTimeFromDropoff: _toInt(j['walking_time_from_dropoff']),
      driverDepartureTime:
          DateTime.parse(j['driver_departure_time'] as String),
      estimatedPickupTime:
          DateTime.parse(j['estimated_pickup_time'] as String),
      availableSeats: _toInt(j['available_seats']),
      pricePerSeat: _toInt(j['price_per_seat']),
    );
  }

  String get walkingDistanceLabel {
    if (walkingDistanceToPickup >= 1000) {
      return '${(walkingDistanceToPickup / 1000).toStringAsFixed(1)} km walk';
    }
    return '${walkingDistanceToPickup} m walk';
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
      routeId: (j['route_id'] ?? j['id']) as String,
      driverUserId: (j['driver_user_id'] ?? j['driver_id']) as String,
      driverName: j['driver_name'] as String? ?? '',
      originName: (j['origin_name'] as String?) ?? 'Origin',
      destinationName: (j['destination_name'] as String?) ?? 'Destination',
      originLat: _toDouble(j['origin_lat']),
      originLng: _toDouble(j['origin_lng']),
      destinationLat: _toDouble(j['destination_lat'] ?? j['dest_lat']),
      destinationLng: _toDouble(j['destination_lng'] ?? j['dest_lng']),
      departureDatetime: DateTime.parse(
        (j['departure_datetime'] ?? j['departure_time']) as String,
      ),
      pricePerSeatTzs: _toInt(
        j['price_per_seat_tzs'] ?? j['price_per_seat'],
      ),
      totalSeats: totalSeats,
      availableSeats: availableSeats,
      vehicleModel: j['vehicle_model'] as String? ?? '',
      vehiclePlate: j['vehicle_plate'] as String? ?? '',
      status: j['status'] as String? ?? 'active',
      encodedPolyline: (j['encoded_polyline'] ?? j['polyline']) as String?,
      driverRating: (j['driver_rating'] as num?)?.toDouble(),
      estimatedArrivalDatetime: j['estimated_arrival_datetime'] != null
          ? DateTime.parse(j['estimated_arrival_datetime'] as String)
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
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        order: j['order'] as int? ?? 0,
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
    this.year,
    this.isActive = false,
  });

  final String id;
  final String make;
  final String model;
  final String plateNumber;
  final int? year;
  final bool isActive;

  String get label {
    final String base = '$make $model'.trim();
    final String withYear =
        year != null && year! > 0 ? '$base ($year)' : base;
    final String normalized = withYear.trim().isEmpty ? 'Vehicle' : withYear;
    return '$normalized · $plateNumber';
  }

  factory DriverVehicleOption.fromJson(Map<String, dynamic> j) {
    return DriverVehicleOption(
      id: (j['id'] ?? j['vehicle_id']) as String,
      make: (j['make'] as String?) ?? '',
      model: (j['model'] as String?) ?? '',
      plateNumber: (j['plate_number'] ?? j['registration_number'] ?? '')
          as String,
      year: _toNullableInt(j['year']),
      isActive: (j['is_active'] as bool?) ?? false,
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw FormatException('Invalid numeric value: $value');
}

int _toInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return double.parse(value).round();
  return fallback;
}

int? _toNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
