import '../../domain/entities/route_entity.dart';

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

  factory RouteDto.fromJson(Map<String, dynamic> j) => RouteDto(
        routeId: j['route_id'] as String,
        driverUserId: j['driver_user_id'] as String,
        driverName: j['driver_name'] as String? ?? '',
        originName: j['origin_name'] as String,
        destinationName: j['destination_name'] as String,
        originLat: (j['origin_lat'] as num).toDouble(),
        originLng: (j['origin_lng'] as num).toDouble(),
        destinationLat: (j['destination_lat'] as num).toDouble(),
        destinationLng: (j['destination_lng'] as num).toDouble(),
        departureDatetime: DateTime.parse(j['departure_datetime'] as String),
        pricePerSeatTzs: j['price_per_seat_tzs'] as int,
        totalSeats: j['total_seats'] as int,
        availableSeats: j['available_seats'] as int,
        vehicleModel: j['vehicle_model'] as String? ?? '',
        vehiclePlate: j['vehicle_plate'] as String? ?? '',
        status: j['status'] as String? ?? 'active',
        encodedPolyline: j['encoded_polyline'] as String?,
        driverRating: (j['driver_rating'] as num?)?.toDouble(),
        estimatedArrivalDatetime: j['estimated_arrival_datetime'] != null
            ? DateTime.parse(j['estimated_arrival_datetime'] as String)
            : null,
        waypoints: (j['waypoints'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) =>
                RouteWaypointDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

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
    required this.origin,
    required this.destination,
    required this.departureDate,
    required this.seats,
  });

  final String origin;
  final String destination;
  final DateTime departureDate;
  final int seats;
}
