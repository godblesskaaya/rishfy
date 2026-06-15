class PaymentRefundDto {
  const PaymentRefundDto({
    required this.refundId,
    required this.amountTzs,
    required this.status,
    required this.reason,
    required this.policy,
    required this.requestedAt,
    this.providerReference,
    this.failureReason,
    this.completedAt,
    this.failedAt,
  });

  final String refundId;
  final int amountTzs;
  final String status;
  final String reason;
  final String policy;
  final String? providerReference;
  final String? failureReason;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final DateTime? failedAt;

  factory PaymentRefundDto.fromJson(Map<String, dynamic> json) {
    return PaymentRefundDto(
      refundId: _readString(json, <String>['refund_id', 'refundId', 'id']) ?? '',
      amountTzs: _readInt(json, <String>['amount_tzs', 'amountTzs']),
      status: _readString(json, <String>['status']) ?? 'requested',
      reason: _readString(json, <String>['reason']) ?? '',
      policy: _readString(json, <String>['policy']) ?? '',
      providerReference: _readString(
        json,
        <String>['provider_reference', 'providerReference'],
      ),
      failureReason: _readString(
        json,
        <String>['failure_reason', 'failureReason'],
      ),
      requestedAt:
          _readDateTime(json, <String>['requested_at', 'requestedAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: _readDateTime(json, <String>['completed_at', 'completedAt']),
      failedAt: _readDateTime(json, <String>['failed_at', 'failedAt']),
    );
  }
}

class PaymentDetailDto {
  const PaymentDetailDto({
    required this.paymentId,
    required this.bookingId,
    required this.amountTzs,
    required this.refundedAmountTzs,
    required this.method,
    required this.status,
    required this.provider,
    required this.internalReference,
    required this.initiatedAt,
    this.providerReference,
    this.failureCode,
    this.failureMessage,
    this.completedAt,
    this.failedAt,
    this.lastRefundAt,
    this.refunds = const <PaymentRefundDto>[],
  });

  final String paymentId;
  final String bookingId;
  final int amountTzs;
  final int refundedAmountTzs;
  final String method;
  final String status;
  final String provider;
  final String internalReference;
  final String? providerReference;
  final String? failureCode;
  final String? failureMessage;
  final DateTime initiatedAt;
  final DateTime? completedAt;
  final DateTime? failedAt;
  final DateTime? lastRefundAt;
  final List<PaymentRefundDto> refunds;

  int get netPaidTzs => amountTzs - refundedAmountTzs;
  bool get hasRefunds => refunds.isNotEmpty || refundedAmountTzs > 0;

  factory PaymentDetailDto.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawRefunds = json['refunds'] is List<dynamic>
        ? json['refunds'] as List<dynamic>
        : <dynamic>[];
    return PaymentDetailDto(
      paymentId: _readString(json, <String>['payment_id', 'paymentId', 'id']) ??
          '',
      bookingId: _readString(json, <String>['booking_id', 'bookingId']) ?? '',
      amountTzs: _readInt(json, <String>['amount_tzs', 'amountTzs', 'amount']),
      refundedAmountTzs: _readInt(
        json,
        <String>['refunded_amount_tzs', 'refundedAmountTzs', 'refunded_amount'],
      ),
      method: _readString(json, <String>['method']) ?? '',
      status: _readString(json, <String>['status']) ?? 'pending',
      provider: _readString(json, <String>['provider']) ?? '',
      internalReference: _readString(
            json,
            <String>['internal_reference', 'internalReference'],
          ) ??
          '',
      providerReference: _readString(
        json,
        <String>['provider_reference', 'providerReference'],
      ),
      failureCode: _readString(json, <String>['failure_code', 'failureCode']),
      failureMessage: _readString(
        json,
        <String>['failure_message', 'failureMessage'],
      ),
      initiatedAt:
          _readDateTime(json, <String>['initiated_at', 'initiatedAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: _readDateTime(json, <String>['completed_at', 'completedAt']),
      failedAt: _readDateTime(json, <String>['failed_at', 'failedAt']),
      lastRefundAt:
          _readDateTime(json, <String>['last_refund_at', 'lastRefundAt']),
      refunds: rawRefunds
          .map((dynamic item) {
            if (item is Map<String, dynamic>) return item;
            if (item is Map) return Map<String, dynamic>.from(item);
            return null;
          })
          .whereType<Map<String, dynamic>>()
          .map(PaymentRefundDto.fromJson)
          .toList(),
    );
  }
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num) {
      return value.toString();
    }
  }
  return null;
}

int _readInt(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
  }
  return 0;
}

DateTime? _readDateTime(Map<String, dynamic> json, List<String> keys) {
  final String? value = _readString(json, keys);
  if (value == null) return null;
  return DateTime.tryParse(value);
}
