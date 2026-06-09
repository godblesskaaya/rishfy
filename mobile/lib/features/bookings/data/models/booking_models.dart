// ignore_for_file: sort_constructors_first

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
    this.passengerName,
    this.confirmationCode,
    this.originName,
    this.destinationName,
    this.departureDatetime,
    this.driverName,
    this.vehiclePlate,
    this.paymentId,
    this.suggestedPickupName,
    this.pickupLat,
    this.pickupLng,
    this.suggestedDropoffName,
    this.dropoffPointLat,
    this.dropoffPointLng,
    this.destinationLat,
    this.destinationLng,
    this.tripId,
    this.journeyState,
    this.routeStatus,
    this.routePolyline,
    this.estimatedPickupTime,
    this.pickupWalkingDistance,
    this.pickupWalkingTime,
    this.dropoffWalkingDistance,
    this.dropoffWalkingTime,
    this.etaToPickupSeconds,
    this.etaToDropoffSeconds,
    this.etaUpdatedAt,
    this.etaApproximate,
    this.etaStale,
    this.driverLat,
    this.driverLng,
    this.driverHeading,
    this.driverSpeedKmh,
    this.driverLocationUpdatedAt,
    this.arrivedPickupAt,
    this.boardedAt,
    this.droppedOffAt,
    this.tripStartedAt,
    this.tripCompletedAt,
    this.journeyCompletedAt,
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
  final String? passengerName;
  final String? confirmationCode;
  final String? originName;
  final String? destinationName;
  final DateTime? departureDatetime;
  final String? driverName;
  final String? vehiclePlate;
  final String? paymentId;
  final String? suggestedPickupName;
  final double? pickupLat;
  final double? pickupLng;
  final String? suggestedDropoffName;
  final double? dropoffPointLat;
  final double? dropoffPointLng;
  final double? destinationLat;
  final double? destinationLng;
  final String? tripId;
  final String? journeyState;
  final String? routeStatus;
  final String? routePolyline;
  final DateTime? estimatedPickupTime;
  final int? pickupWalkingDistance;
  final int? pickupWalkingTime;
  final int? dropoffWalkingDistance;
  final int? dropoffWalkingTime;
  final int? etaToPickupSeconds;
  final int? etaToDropoffSeconds;
  final DateTime? etaUpdatedAt;
  final bool? etaApproximate;
  final bool? etaStale;
  final double? driverLat;
  final double? driverLng;
  final double? driverHeading;
  final double? driverSpeedKmh;
  final DateTime? driverLocationUpdatedAt;
  final DateTime? arrivedPickupAt;
  final DateTime? boardedAt;
  final DateTime? droppedOffAt;
  final DateTime? tripStartedAt;
  final DateTime? tripCompletedAt;
  final DateTime? journeyCompletedAt;

  factory BookingDto.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> data = _readMap(j, <String>['data']) ?? j;
    final Map<String, dynamic> booking =
        _readMap(data, <String>['booking']) ?? data;
    final Map<String, dynamic> trip = _readMap(data, <String>['trip']) ??
        _readMap(booking, <String>['trip']) ??
        <String, dynamic>{};
    final Map<String, dynamic> tripContext =
        _readMap(data, <String>['trip_context', 'journey_context']) ??
            _readMap(booking, <String>['trip_context', 'journey_context']) ??
            <String, dynamic>{};
    final Map<String, dynamic> pickupPoint =
        _readMap(tripContext, <String>['pickup_point']) ??
            _readMap(booking, <String>['pickup_point']) ??
            <String, dynamic>{};
    final Map<String, dynamic> dropoffPoint =
        _readMap(tripContext, <String>['dropoff_point']) ??
            _readMap(booking, <String>['dropoff_point']) ??
            <String, dynamic>{};
    final Map<String, dynamic> driverLocation =
        _readMap(tripContext, <String>['driver_location']) ??
            _readMap(data, <String>['driver_location']) ??
            <String, dynamic>{};

    return BookingDto(
      bookingId: _readRequiredString(booking, <String>['booking_id', 'id']),
      routeId: _readRequiredString(booking, <String>['route_id']),
      passengerUserId: _readString(
            booking,
            <String>['passenger_user_id', 'passenger_id'],
          ) ??
          '',
      seatCount: _toInt(booking['seat_count'] ?? booking['seats_booked']),
      totalPriceTzs:
          _toInt(booking['total_price'] ?? booking['total_price_tzs']),
      status: _readRequiredString(booking, <String>['status']),
      paymentStatus:
          _readString(booking, <String>['payment_status']) ?? 'pending',
      createdAt: _parseDateTime(booking['created_at']),
      driverId: _readString(booking, <String>['driver_id']),
      passengerName: _readString(
        booking,
        <String>['passenger_name', 'passengerName'],
      ),
      confirmationCode: _readString(booking, <String>['confirmation_code']),
      originName: _readString(booking, <String>['origin_name']),
      destinationName:
          _readString(booking, <String>['destination_name', 'dropoff_name']),
      departureDatetime:
          _readString(booking, <String>['departure_datetime']) != null
              ? _parseDateTime(booking['departure_datetime'])
              : null,
      driverName: _readString(booking, <String>['driver_name']),
      vehiclePlate: _readString(booking, <String>['vehicle_plate']),
      paymentId: _readString(booking, <String>['payment_id']),
      suggestedPickupName: _readString(
            booking,
            <String>['suggested_pickup_name', 'pickup_point_label'],
          ) ??
          _readString(pickupPoint, <String>['label', 'name']),
      pickupLat: _toDouble(
        pickupPoint['lat'] ??
            booking['pickup_point_lat'] ??
            booking['pickupPointLat'] ??
            booking['pickup_lat'] ??
            booking['pickupLat'],
      ),
      pickupLng: _toDouble(
        pickupPoint['lng'] ??
            pickupPoint['lon'] ??
            booking['pickup_point_lng'] ??
            booking['pickupPointLng'] ??
            booking['pickup_lng'] ??
            booking['pickupLng'],
      ),
      suggestedDropoffName: _readString(
            booking,
            <String>[
              'suggested_dropoff_name',
              'dropoff_point_label',
              'dropoff_name',
            ],
          ) ??
          _readString(dropoffPoint, <String>['label', 'name']),
      dropoffPointLat: _toDouble(
        dropoffPoint['lat'] ??
            booking['dropoff_point_lat'] ??
            booking['dropoffPointLat'] ??
            booking['dropoff_lat'] ??
            booking['dropoffLat'],
      ),
      dropoffPointLng: _toDouble(
        dropoffPoint['lng'] ??
            dropoffPoint['lon'] ??
            booking['dropoff_point_lng'] ??
            booking['dropoffPointLng'] ??
            booking['dropoff_lng'] ??
            booking['dropoffLng'],
      ),
      destinationLat: _toDouble(
        booking['destination_lat'] ??
            booking['final_destination_lat'] ??
            booking['dropoff_lat'] ??
            booking['dropoffLat'] ??
            booking['dropoff_point_lat'] ??
            booking['dropoffPointLat'],
      ),
      destinationLng: _toDouble(
        booking['destination_lng'] ??
            booking['final_destination_lng'] ??
            booking['dropoff_lng'] ??
            booking['dropoffLng'] ??
            booking['dropoff_point_lng'] ??
            booking['dropoffPointLng'],
      ),
      tripId: _readString(
            trip,
            <String>['trip_id', 'id'],
          ) ??
          _readString(booking, <String>['trip_id']) ??
          _readString(tripContext, <String>['trip_id']),
      journeyState: _readString(
            tripContext,
            <String>['journey_state', 'state', 'booking_journey_state'],
          ) ??
          _readString(
              booking, <String>['journey_state', 'booking_journey_state']) ??
          _readString(trip, <String>['journey_state', 'state']) ??
          _readString(booking, <String>['status']),
      routeStatus: _readString(
            tripContext,
            <String>['route_status'],
          ) ??
          _readString(booking, <String>['route_status']) ??
          _readString(trip, <String>['route_status', 'status']),
      routePolyline: _readString(
            tripContext,
            <String>['route_polyline', 'encoded_polyline'],
          ) ??
          _readString(booking, <String>['route_polyline', 'encoded_polyline']),
      estimatedPickupTime: _parseNullableDateTime(
        tripContext['estimated_pickup_time'] ??
            booking['estimated_pickup_time'] ??
            booking['estimatedPickupTime'],
      ),
      pickupWalkingDistance: _toNullableInt(
        tripContext['pickup_walking_distance'] ??
            booking['pickup_walking_distance'] ??
            booking['pickupWalkingDistance'],
      ),
      pickupWalkingTime: _toNullableInt(
        tripContext['pickup_walking_time'] ??
            booking['pickup_walking_time'] ??
            booking['pickupWalkingTime'],
      ),
      dropoffWalkingDistance: _toNullableInt(
        tripContext['dropoff_walking_distance'] ??
            booking['dropoff_walking_distance'] ??
            booking['dropoffWalkingDistance'],
      ),
      dropoffWalkingTime: _toNullableInt(
        tripContext['dropoff_walking_time'] ??
            booking['dropoff_walking_time'] ??
            booking['dropoffWalkingTime'],
      ),
      etaToPickupSeconds: _toNullableInt(
        tripContext['eta_to_pickup_seconds'] ??
            tripContext['pickup_eta_seconds'] ??
            booking['eta_to_pickup_seconds'],
      ),
      etaToDropoffSeconds: _toNullableInt(
        tripContext['eta_to_dropoff_seconds'] ??
            tripContext['dropoff_eta_seconds'] ??
            booking['eta_to_dropoff_seconds'],
      ),
      etaUpdatedAt: _parseNullableDateTime(
        tripContext['eta_updated_at'] ?? booking['eta_updated_at'],
      ),
      etaApproximate: _toBool(
        tripContext['eta_approximate'] ?? booking['eta_approximate'],
      ),
      etaStale: _toBool(
        tripContext['eta_stale'] ?? booking['eta_stale'],
      ),
      driverLat: _toDouble(
        driverLocation['lat'] ?? booking['driver_lat'],
      ),
      driverLng: _toDouble(
        driverLocation['lng'] ?? driverLocation['lon'] ?? booking['driver_lng'],
      ),
      driverHeading: _toDouble(
        driverLocation['heading'] ?? driverLocation['bearing'],
      ),
      driverSpeedKmh: _toDouble(
        driverLocation['speed_kmh'] ?? driverLocation['speedKmh'],
      ),
      driverLocationUpdatedAt: _parseNullableDateTime(
        driverLocation['timestamp'] ?? booking['driver_location_updated_at'],
      ),
      arrivedPickupAt: _parseNullableDateTime(booking['arrived_pickup_at']),
      boardedAt: _parseNullableDateTime(booking['boarded_at']),
      droppedOffAt: _parseNullableDateTime(booking['dropped_off_at']),
      tripStartedAt: _parseNullableDateTime(
        booking['trip_started_at'] ?? trip['actual_start_time'],
      ),
      tripCompletedAt: _parseNullableDateTime(
        booking['trip_completed_at'] ?? trip['actual_end_time'],
      ),
      journeyCompletedAt: _parseNullableDateTime(
        booking['journey_completed_at'],
      ),
    );
  }

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
        passengerName: passengerName,
        confirmationCode: confirmationCode,
        originName: originName,
        destinationName: destinationName,
        departureDatetime: departureDatetime,
        driverName: driverName,
        vehiclePlate: vehiclePlate,
        paymentId: paymentId,
        suggestedPickupName: suggestedPickupName,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        suggestedDropoffName: suggestedDropoffName,
        dropoffPointLat: dropoffPointLat,
        dropoffPointLng: dropoffPointLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        tripId: tripId,
        journeyState: journeyState,
        routeStatus: routeStatus,
        routePolyline: routePolyline,
        estimatedPickupTime: estimatedPickupTime,
        pickupWalkingDistance: pickupWalkingDistance,
        pickupWalkingTime: pickupWalkingTime,
        dropoffWalkingDistance: dropoffWalkingDistance,
        dropoffWalkingTime: dropoffWalkingTime,
        etaToPickupSeconds: etaToPickupSeconds,
        etaToDropoffSeconds: etaToDropoffSeconds,
        etaUpdatedAt: etaUpdatedAt,
        etaApproximate: etaApproximate,
        etaStale: etaStale,
        driverLat: driverLat,
        driverLng: driverLng,
        driverHeading: driverHeading,
        driverSpeedKmh: driverSpeedKmh,
        driverLocationUpdatedAt: driverLocationUpdatedAt,
        arrivedPickupAt: arrivedPickupAt,
        boardedAt: boardedAt,
        droppedOffAt: droppedOffAt,
        tripStartedAt: tripStartedAt,
        tripCompletedAt: tripCompletedAt,
        journeyCompletedAt: journeyCompletedAt,
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
    this.suggestedDropoffName,
    this.dropoffPointLat,
    this.dropoffPointLng,
    this.estimatedPickupTime,
    this.pickupWalkingDistance,
    this.pickupWalkingTime,
    this.dropoffWalkingDistance,
    this.dropoffWalkingTime,
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
  final String? suggestedDropoffName;
  final double? dropoffPointLat;
  final double? dropoffPointLng;
  final DateTime? estimatedPickupTime;
  final int? pickupWalkingDistance;
  final int? pickupWalkingTime;
  final int? dropoffWalkingDistance;
  final int? dropoffWalkingTime;

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
        if (suggestedPickupName != null)
          'suggestedPickupName': suggestedPickupName,
        if (pickupPointLat != null) 'pickupPointLat': pickupPointLat,
        if (pickupPointLng != null) 'pickupPointLng': pickupPointLng,
        if (suggestedDropoffName != null)
          'suggestedDropoffName': suggestedDropoffName,
        if (dropoffPointLat != null) 'dropoffPointLat': dropoffPointLat,
        if (dropoffPointLng != null) 'dropoffPointLng': dropoffPointLng,
        if (estimatedPickupTime != null)
          'estimatedPickupTime': estimatedPickupTime!.toUtc().toIso8601String(),
        if (pickupWalkingDistance != null)
          'pickupWalkingDistance': pickupWalkingDistance,
        if (pickupWalkingTime != null) 'pickupWalkingTime': pickupWalkingTime,
        if (dropoffWalkingDistance != null)
          'dropoffWalkingDistance': dropoffWalkingDistance,
        if (dropoffWalkingTime != null)
          'dropoffWalkingTime': dropoffWalkingTime,
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

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool? _toBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return null;
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
  return _toInt(value, fallback: 0);
}

DateTime _parseDateTime(dynamic value, {DateTime? fallback}) {
  if (value == null) return fallback ?? DateTime.now();
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return fallback ?? DateTime.now();
  }
}

DateTime? _parseNullableDateTime(dynamic value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return null;
  }
}

String _readRequiredString(Map<String, dynamic> json, List<String> keys) {
  final String? value = _readString(json, keys);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required string for keys: $keys');
  }
  return value;
}

Map<String, dynamic>? _readMap(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (dynamic mapKey, dynamic mapValue) => MapEntry(
          mapKey.toString(),
          mapValue,
        ),
      );
    }
  }
  return null;
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
