import 'package:equatable/equatable.dart';

class RouteEntity extends Equatable {
  const RouteEntity({
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
    this.waypoints = const <RouteWaypoint>[],
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
  final List<RouteWaypoint> waypoints;

  @override
  List<Object?> get props => <Object?>[routeId];
}

class RouteWaypoint extends Equatable {
  const RouteWaypoint({
    required this.name,
    required this.lat,
    required this.lng,
    required this.order,
  });

  final String name;
  final double lat;
  final double lng;
  final int order;

  @override
  List<Object?> get props => <Object?>[lat, lng];
}
