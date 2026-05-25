// ignore_for_file: sort_constructors_first

class DriverLocationUpdate {
  const DriverLocationUpdate({
    required this.driverUserId,
    required this.lat,
    required this.lng,
    required this.heading,
    required this.speedKmh,
    required this.timestamp,
    this.tripId,
    this.routeRunId,
    this.bookingId,
    this.journeyState,
    this.routeStatus,
    this.stopLabel,
    this.stopType,
    this.etaToPickupSeconds,
    this.etaToDropoffSeconds,
    this.etaApproximate,
    this.etaStale,
    this.distanceToActiveStopMeters,
    this.proximityState,
    this.currentRouteFraction,
    this.remainingRouteFraction,
  });

  final String driverUserId;
  final double lat;
  final double lng;
  final double heading;
  final double speedKmh;
  final DateTime timestamp;
  final String? tripId;
  final String? routeRunId;
  final String? bookingId;
  final String? journeyState;
  final String? routeStatus;
  final String? stopLabel;
  final String? stopType;
  final int? etaToPickupSeconds;
  final int? etaToDropoffSeconds;
  final bool? etaApproximate;
  final bool? etaStale;
  final int? distanceToActiveStopMeters;
  final String? proximityState;
  final double? currentRouteFraction;
  final double? remainingRouteFraction;

  factory DriverLocationUpdate.fromJson(Map<String, dynamic> j) =>
      DriverLocationUpdate(
        driverUserId: j['driver_user_id'] as String? ?? '',
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        heading: _toNullableDouble(j['heading'] ?? j['bearing']) ?? 0,
        speedKmh: _toNullableDouble(j['speed_kmh'] ?? j['speedKmh']) ?? 0,
        timestamp: j['timestamp'] != null
            ? _parseDateTime(j['timestamp'])
            : DateTime.now(),
        tripId: j['trip_id']?.toString() ?? j['tripId']?.toString(),
        routeRunId: j['route_run_id']?.toString() ?? j['routeRunId']?.toString(),
        bookingId: j['booking_id']?.toString() ?? j['bookingId']?.toString(),
        journeyState: j['journey_state']?.toString() ?? j['state']?.toString(),
        routeStatus: j['route_status']?.toString(),
        stopLabel:
            j['stop_label']?.toString() ?? j['next_stop_label']?.toString(),
        stopType: j['stop_type']?.toString() ??
            j['next_stop_type']?.toString() ??
            j['active_stop_type']?.toString(),
        etaToPickupSeconds: _resolvePickupEta(j),
        etaToDropoffSeconds: _resolveDropoffEta(j),
        etaApproximate: _toBool(j['eta_approximate']),
        etaStale: _toBool(j['eta_stale']),
        distanceToActiveStopMeters: _toNullableInt(
          j['distance_to_active_stop_meters'],
        ),
        proximityState: j['proximity_state']?.toString(),
        currentRouteFraction: _toNullableDouble(j['current_route_fraction']),
        remainingRouteFraction:
            _toNullableDouble(j['remaining_route_fraction']),
      );

  factory DriverLocationUpdate.fromBookingContext({
    required String driverUserId,
    required double lat,
    required double lng,
    required DateTime timestamp,
    double heading = 0,
    double speedKmh = 0,
    String? tripId,
    String? routeRunId,
    String? bookingId,
    String? journeyState,
    String? routeStatus,
    String? stopLabel,
    String? stopType,
    int? etaToPickupSeconds,
    int? etaToDropoffSeconds,
    bool? etaApproximate,
    bool? etaStale,
    int? distanceToActiveStopMeters,
    String? proximityState,
    double? currentRouteFraction,
    double? remainingRouteFraction,
  }) =>
      DriverLocationUpdate(
        driverUserId: driverUserId,
        lat: lat,
        lng: lng,
        heading: heading,
        speedKmh: speedKmh,
        timestamp: timestamp,
        tripId: tripId,
        routeRunId: routeRunId,
        bookingId: bookingId,
        journeyState: journeyState,
        routeStatus: routeStatus,
        stopLabel: stopLabel,
        stopType: stopType,
        etaToPickupSeconds: etaToPickupSeconds,
        etaToDropoffSeconds: etaToDropoffSeconds,
        etaApproximate: etaApproximate,
        etaStale: etaStale,
        distanceToActiveStopMeters: distanceToActiveStopMeters,
        proximityState: proximityState,
        currentRouteFraction: currentRouteFraction,
        remainingRouteFraction: remainingRouteFraction,
      );

  static double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static int? _resolvePickupEta(Map<String, dynamic> json) {
    final int? explicit = _toNullableInt(
      json['eta_to_pickup_seconds'] ?? json['pickup_eta_seconds'],
    );
    if (explicit != null) {
      return explicit;
    }
    if (json['active_stop_type']?.toString() == 'pickup') {
      return _toNullableInt(json['eta_seconds']);
    }
    return null;
  }

  static int? _resolveDropoffEta(Map<String, dynamic> json) {
    final int? explicit = _toNullableInt(
      json['eta_to_dropoff_seconds'] ?? json['dropoff_eta_seconds'],
    );
    if (explicit != null) {
      return explicit;
    }
    if (json['active_stop_type']?.toString() == 'dropoff') {
      return _toNullableInt(json['eta_seconds']);
    }
    return null;
  }

  static bool? _toBool(dynamic value) {
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

  static DateTime _parseDateTime(dynamic value) {
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tripId': tripId,
        'routeRunId': routeRunId,
        'bookingId': bookingId,
        'lat': lat,
        'lng': lng,
        'bearing': heading,
        'speedKmh': speedKmh,
        'timestamp': timestamp.toIso8601String(),
        'journeyState': journeyState,
        'routeStatus': routeStatus,
        'stopLabel': stopLabel,
        'stopType': stopType,
        'etaToPickupSeconds': etaToPickupSeconds,
        'etaToDropoffSeconds': etaToDropoffSeconds,
        'etaApproximate': etaApproximate,
        'etaStale': etaStale,
        'distanceToActiveStopMeters': distanceToActiveStopMeters,
        'proximityState': proximityState,
        'currentRouteFraction': currentRouteFraction,
        'remainingRouteFraction': remainingRouteFraction,
      };
}
