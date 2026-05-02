import '../../domain/entities/booking_entity.dart';

class BookingDto {
  const BookingDto({
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

  factory BookingDto.fromJson(Map<String, dynamic> j) => BookingDto(
        bookingId: j['booking_id'] as String,
        routeId: j['route_id'] as String,
        passengerUserId: j['passenger_user_id'] as String,
        seatCount: j['seat_count'] as int,
        totalPriceTzs: j['total_price'] as int,
        status: j['status'] as String,
        paymentStatus: j['payment_status'] as String? ?? 'pending',
        createdAt: DateTime.parse(j['created_at'] as String),
        confirmationCode: j['confirmation_code'] as String?,
        originName: j['origin_name'] as String?,
        destinationName: j['destination_name'] as String?,
        departureDatetime: j['departure_datetime'] != null
            ? DateTime.parse(j['departure_datetime'] as String)
            : null,
        driverName: j['driver_name'] as String?,
        vehiclePlate: j['vehicle_plate'] as String?,
        paymentId: j['payment_id'] as String?,
      );

  BookingEntity toDomain() => BookingEntity(
        bookingId: bookingId,
        routeId: routeId,
        passengerUserId: passengerUserId,
        seatCount: seatCount,
        totalPriceTzs: totalPriceTzs,
        status: status,
        paymentStatus: paymentStatus,
        createdAt: createdAt,
        confirmationCode: confirmationCode,
        originName: originName,
        destinationName: destinationName,
        departureDatetime: departureDatetime,
        driverName: driverName,
        vehiclePlate: vehiclePlate,
        paymentId: paymentId,
      );
}

class CreateBookingRequest {
  const CreateBookingRequest({
    required this.routeId,
    required this.seatCount,
    required this.paymentMethod,
    required this.payerPhone,
  });

  final String routeId;
  final int seatCount;
  final String paymentMethod;
  final String payerPhone;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'route_id': routeId,
        'seat_count': seatCount,
        'payment_method': paymentMethod,
        'payer_phone': payerPhone,
      };
}

class InitiatePaymentResponse {
  const InitiatePaymentResponse({
    required this.bookingId,
    required this.paymentId,
    required this.status,
    this.ussdCode,
    this.providerReference,
  });

  final String bookingId;
  final String paymentId;
  final String status;
  final String? ussdCode;
  final String? providerReference;

  factory InitiatePaymentResponse.fromJson(Map<String, dynamic> j) =>
      InitiatePaymentResponse(
        bookingId: j['booking_id'] as String,
        paymentId: j['payment_id'] as String,
        status: j['status'] as String,
        ussdCode: j['ussd_code'] as String?,
        providerReference: j['provider_reference'] as String?,
      );
}
