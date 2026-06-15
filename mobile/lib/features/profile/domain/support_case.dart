class SupportCase {
  const SupportCase({
    required this.id,
    required this.subject,
    required this.message,
    required this.category,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.bookingId,
    this.lastSupportResponseAt,
    this.resolvedAt,
    this.closedAt,
  });

  final String id;
  final String subject;
  final String message;
  final String category;
  final String status;
  final String priority;
  final String? bookingId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSupportResponseAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;

  bool get isOpen => status == 'open' || status == 'waiting';

  factory SupportCase.fromJson(Map<String, dynamic> json) {
    return SupportCase(
      id: json['id'] as String? ?? '',
      subject: json['subject'] as String? ?? 'Support case',
      message: json['message'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      status: json['status'] as String? ?? 'open',
      priority: json['priority'] as String? ?? 'normal',
      bookingId: _readString(json, 'bookingId', 'booking_id'),
      createdAt: _readDate(json, 'createdAt', 'created_at'),
      updatedAt: _readDate(json, 'updatedAt', 'updated_at'),
      lastSupportResponseAt: _readNullableDate(
        json,
        'lastSupportResponseAt',
        'last_support_response_at',
      ),
      resolvedAt: _readNullableDate(json, 'resolvedAt', 'resolved_at'),
      closedAt: _readNullableDate(json, 'closedAt', 'closed_at'),
    );
  }

  static DateTime _readDate(
    Map<String, dynamic> json,
    String camelKey,
    String snakeKey,
  ) {
    return _readNullableDate(json, camelKey, snakeKey) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime? _readNullableDate(
    Map<String, dynamic> json,
    String camelKey,
    String snakeKey,
  ) {
    final Object? value = json[camelKey] ?? json[snakeKey];
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _readString(
    Map<String, dynamic> json,
    String camelKey,
    String snakeKey,
  ) {
    final Object? value = json[camelKey] ?? json[snakeKey];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
