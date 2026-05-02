import 'package:equatable/equatable.dart';

class BookingEntity extends Equatable {
  const BookingEntity({
    required this.bookingId,
    required this.routeId,
    required this.passengerUserId,
    required this.seatCount,
    required this.totalPriceTzs,
    required this.status,
    required this.paymentStatus,
    required this.createdAt,
    this.confirmationCode,
    this.originName,
    this.destinationName,
    this.departureDatetime,
    this.driverName,
    this.vehiclePlate,
    this.paymentId,
  });

  final String bookingId;
  final String routeId;
  final String passengerUserId;
  final int seatCount;
  final int totalPriceTzs;
  final String status;
  final String paymentStatus;
  final DateTime createdAt;
  final String? confirmationCode;
  final String? originName;
  final String? destinationName;
  final DateTime? departureDatetime;
  final String? driverName;
  final String? vehiclePlate;
  final String? paymentId;

  @override
  List<Object?> get props => <Object?>[bookingId];
}
