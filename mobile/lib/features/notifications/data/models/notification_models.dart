class NotificationDto {
  const NotificationDto({
    required this.notificationId,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    this.data,
  });

  final String notificationId;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? data;

  factory NotificationDto.fromJson(Map<String, dynamic> j) => NotificationDto(
        notificationId: _readString(
          j,
          <String>['notification_id', 'id'],
        ),
        title: _readString(j, <String>['title']),
        body: _readString(j, <String>['body', 'message']),
        type: (j['type'] ?? j['channel'] ?? j['template_key']) as String? ??
            'info',
        isRead: _readBool(j, <String>['is_read', 'read']) ?? false,
        createdAt: DateTime.parse(
          _readString(j, <String>['created_at', 'createdAt']),
        ),
        data: j['data'] is Map<String, dynamic>
            ? j['data'] as Map<String, dynamic>
            : (j['data'] is Map
                ? Map<String, dynamic>.from(j['data'] as Map)
                : null),
      );
}

String _readString(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value == null) {
      continue;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return value.toString();
  }
  throw FormatException('Missing required string for keys: $keys');
}

bool? _readBool(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final String key in keys) {
    final dynamic value = json[key];
    if (value == null) {
      continue;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
  }
  return null;
}
