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
        bookingId: _readRequiredString(j, <String>['booking_id', 'id']),
        routeId: _readRequiredString(j, <String>['route_id']),
        passengerUserId:
            _readString(j, <String>['passenger_user_id', 'passenger_id']) ?? '',
        seatCount: _toInt(j['seat_count'] ?? j['seats_booked']),
        totalPriceTzs: _toInt(j['total_price'] ?? j['total_price_tzs']),
        status: _readRequiredString(j, <String>['status']),
        paymentStatus: _readString(j, <String>['payment_status']) ?? 'pending',
        createdAt: _parseDateTime(j['created_at']),
        driverId: _readString(j, <String>['driver_id']),
        confirmationCode: _readString(j, <String>['confirmation_code']),
        originName: _readString(j, <String>['origin_name']),
        destinationName: _readString(j, <String>['destination_name']),
        departureDatetime: _readString(j, <String>['departure_datetime']) != null
            ? _parseDateTime(j['departure_datetime'])
            : null,
        driverName: _readString(j, <String>['driver_name']),
        vehiclePlate: _readString(j, <String>['vehicle_plate']),
        paymentId: _readString(j, <String>['payment_id']),
        suggestedPickupName: _readString(j, <String>['suggested_pickup_name']),
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
        bookingId: _readRequiredString(j, <String>['booking_id', 'bookingId']),
        paymentId: _readRequiredString(j, <String>['payment_id', 'paymentId']),
        status: _readRequiredString(j, <String>['status']),
        ussdCode: _readString(j, <String>['ussd_code', 'instructions']),
        providerReference: _readString(
          j,
          <String>['provider_reference', 'providerReference'],
        ),
      );
}

int _toInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return double.tryParse(value)?.round() ?? fallback;
  return fallback;
}

DateTime _parseDateTime(dynamic value, {DateTime? fallback}) {
  if (value == null) return fallback ?? DateTime.now();
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return fallback ?? DateTime.now();
  }
}

String _readRequiredString(Map<String, dynamic> json, List<String> keys) {
  final String? value = _readString(json, keys);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required string for keys: $keys');
  }
  return value;
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value == null) {
      continue;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }
  return null;
}
