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
        notificationId: j['notification_id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        type: j['type'] as String? ?? 'info',
        isRead: j['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
        data: j['data'] as Map<String, dynamic>?,
      );
}
