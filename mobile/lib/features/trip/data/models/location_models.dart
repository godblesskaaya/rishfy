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
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        heading: (j['heading'] as num?)?.toDouble() ?? 0,
        speedKmh: (j['speed_kmh'] as num?)?.toDouble() ?? 0,
        timestamp: j['timestamp'] != null
            ? DateTime.parse(j['timestamp'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'heading': heading,
        'speed_kmh': speedKmh,
        'timestamp': timestamp.toIso8601String(),
      };
}
