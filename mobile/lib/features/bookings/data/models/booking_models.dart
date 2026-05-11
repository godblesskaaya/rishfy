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
    this.driverId,
    this.confirmationCode,
    this.originName,
    this.destinationName,
    this.departureDatetime,
    this.driverName,
    this.vehiclePlate,
    this.paymentId,
    this.suggestedPickupName,
  });

  final String bookingId;
  final String routeId;
  final String passengerUserId;
  final int seatCount;
  final int totalPriceTzs;
  final String status;
  final String paymentStatus;
  final DateTime createdAt;
  final String? driverId;
  final String? confirmationCode;
  final String? originName;
  final String? destinationName;
  final DateTime? departureDatetime;
  final String? driverName;
  final String? vehiclePlate;
  final String? paymentId;
  final String? suggestedPickupName;

  factory BookingDto.fromJson(Map<String, dynamic> j) => BookingDto(
        bookingId: (j['booking_id'] ?? j['id']) as String,
        routeId: j['route_id'] as String,
        passengerUserId:
            (j['passenger_user_id'] ?? j['passenger_id']) as String? ?? '',
        seatCount: _toInt(j['seat_count'] ?? j['seats_booked']),
        totalPriceTzs: _toInt(j['total_price'] ?? j['total_price_tzs']),
        status: j['status'] as String,
        paymentStatus: j['payment_status'] as String? ?? 'pending',
        createdAt: DateTime.parse(j['created_at'] as String),
        driverId: j['driver_id'] as String?,
        confirmationCode: j['confirmation_code'] as String?,
        originName: j['origin_name'] as String?,
        destinationName: j['destination_name'] as String?,
        departureDatetime: j['departure_datetime'] != null
            ? DateTime.parse(j['departure_datetime'] as String)
            : null,
        driverName: j['driver_name'] as String?,
        vehiclePlate: j['vehicle_plate'] as String?,
        paymentId: j['payment_id'] as String?,
        suggestedPickupName: j['suggested_pickup_name'] as String?,
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
        driverId: driverId,
        confirmationCode: confirmationCode,
        originName: originName,
        destinationName: destinationName,
        departureDatetime: departureDatetime,
        driverName: driverName,
        vehiclePlate: vehiclePlate,
        paymentId: paymentId,
        suggestedPickupName: suggestedPickupName,
      );
}

class CreateBookingRequest {
  const CreateBookingRequest({
    required this.routeId,
    required this.driverId,
    required this.seatsBooked,
    required this.pricePerSeat,
    required this.paymentMethod,
    required this.payerPhone,
    required this.idempotencyKey,
    this.pickupName,
    this.dropoffName,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.suggestedPickupName,
    this.pickupPointLat,
    this.pickupPointLng,
    this.dropoffPointLat,
    this.dropoffPointLng,
    this.estimatedPickupTime,
    this.pickupWalkingDistance,
    this.pickupWalkingTime,
    this.dropoffWalkingDistance,
  });

  final String routeId;
  final String driverId;
  final int seatsBooked;
  final int pricePerSeat;
  final String paymentMethod;
  final String payerPhone;
  final String idempotencyKey;
  final String? pickupName;
  final String? dropoffName;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? suggestedPickupName;
  final double? pickupPointLat;
  final double? pickupPointLng;
  final double? dropoffPointLat;
  final double? dropoffPointLng;
  final DateTime? estimatedPickupTime;
  final int? pickupWalkingDistance;
  final int? pickupWalkingTime;
  final int? dropoffWalkingDistance;

  int get totalAmountTzs => seatsBooked * pricePerSeat;

  Map<String, dynamic> toBookingJson() => <String, dynamic>{
        'routeId': routeId,
        'driverId': driverId,
        'seatsBooked': seatsBooked,
        'pricePerSeat': pricePerSeat,
        'idempotencyKey': idempotencyKey,
        if (pickupName != null) 'pickupName': pickupName,
        if (dropoffName != null) 'dropoffName': dropoffName,
        if (pickupLat != null) 'pickupLat': pickupLat,
        if (pickupLng != null) 'pickupLng': pickupLng,
        if (dropoffLat != null) 'dropoffLat': dropoffLat,
        if (dropoffLng != null) 'dropoffLng': dropoffLng,
        if (suggestedPickupName != null) 'suggestedPickupName': suggestedPickupName,
        if (pickupPointLat != null) 'pickupPointLat': pickupPointLat,
        if (pickupPointLng != null) 'pickupPointLng': pickupPointLng,
        if (dropoffPointLat != null) 'dropoffPointLat': dropoffPointLat,
        if (dropoffPointLng != null) 'dropoffPointLng': dropoffPointLng,
        if (estimatedPickupTime != null)
          'estimatedPickupTime': estimatedPickupTime!.toUtc().toIso8601String(),
        if (pickupWalkingDistance != null)
          'pickupWalkingDistance': pickupWalkingDistance,
        if (pickupWalkingTime != null) 'pickupWalkingTime': pickupWalkingTime,
        if (dropoffWalkingDistance != null)
          'dropoffWalkingDistance': dropoffWalkingDistance,
      };

  Map<String, dynamic> toPaymentJson(String bookingId) => <String, dynamic>{
        'bookingId': bookingId,
        'amountTzs': totalAmountTzs,
        'method': paymentMethod,
        'payerPhone': payerPhone,
        'idempotencyKey': idempotencyKey,
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
        bookingId: (j['booking_id'] ?? j['bookingId']) as String,
        paymentId: (j['payment_id'] ?? j['paymentId']) as String,
        status: j['status'] as String,
        ussdCode: (j['ussd_code'] ?? j['instructions']) as String?,
        providerReference:
            (j['provider_reference'] ?? j['providerReference']) as String?,
      );
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return double.parse(value).round();
  throw FormatException('Invalid integer value: $value');
}
