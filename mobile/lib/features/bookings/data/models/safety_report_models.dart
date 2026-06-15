class SafetyReportDto {
  const SafetyReportDto({
    required this.reportId,
    required this.bookingId,
    required this.status,
    required this.createdAt,
    this.routeId,
    this.reason,
    this.reporterRole,
    this.pickupName,
    this.dropoffName,
    this.paymentStatus,
  });

  final String reportId;
  final String bookingId;
  final String? routeId;
  final String status;
  final String? reason;
  final String? reporterRole;
  final String? pickupName;
  final String? dropoffName;
  final String? paymentStatus;
  final DateTime createdAt;

  factory SafetyReportDto.fromJson(Map<String, dynamic> json) {
    return SafetyReportDto(
      reportId: _readString(json, <String>['reportId', 'report_id', 'id']) ?? '',
      bookingId: _readString(json, <String>['bookingId', 'booking_id']) ?? '',
      routeId: _readString(json, <String>['routeId', 'route_id']),
      status: _readString(json, <String>['status']) ?? 'submitted',
      reason: _readString(json, <String>['reason']),
      reporterRole: _readString(json, <String>['reporterRole', 'reporter_role']),
      pickupName: _readString(json, <String>['pickupName', 'pickup_name']),
      dropoffName: _readString(json, <String>['dropoffName', 'dropoff_name']),
      paymentStatus: _readString(json, <String>['paymentStatus', 'payment_status']),
      createdAt: DateTime.tryParse(
            _readString(json, <String>['createdAt', 'created_at']) ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}
