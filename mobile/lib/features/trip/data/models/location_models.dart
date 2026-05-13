class DriverLocationUpdate {
  const DriverLocationUpdate({
    required this.driverUserId,
    required this.lat,
    required this.lng,
    required this.heading,
    required this.speedKmh,
    required this.timestamp,
  });

  final String driverUserId;
  final double lat;
  final double lng;
  final double heading;
  final double speedKmh;
  final DateTime timestamp;

  factory DriverLocationUpdate.fromJson(Map<String, dynamic> j) =>
      DriverLocationUpdate(
        driverUserId: j['driver_user_id'] as String? ?? '',
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        heading: _toNullableDouble(j['heading']) ?? 0,
        speedKmh: _toNullableDouble(j['speed_kmh']) ?? 0,
        timestamp: j['timestamp'] != null
            ? _parseDateTime(j['timestamp'])
            : DateTime.now(),
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

  static DateTime _parseDateTime(dynamic value) {
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'bearing': heading,
        'speedKmh': speedKmh,
        'timestamp': timestamp.toIso8601String(),
      };
}
