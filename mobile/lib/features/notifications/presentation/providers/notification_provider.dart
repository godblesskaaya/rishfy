import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/models/notification_models.dart';

class NotificationState {
  const NotificationState({
    this.notifications = const <NotificationDto>[],
    this.unreadCount = 0,
    this.isLoading = false,
    this.error,
  });

  final List<NotificationDto> notifications;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  NotificationState copyWith({
    List<NotificationDto>? notifications,
    int? unreadCount,
    bool? isLoading,
    String? error,
  }) =>
      NotificationState(
        notifications: notifications ?? this.notifications,
        unreadCount: unreadCount ?? this.unreadCount,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

final StateNotifierProvider<NotificationNotifier, NotificationState>
    notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>(
  (Ref ref) => NotificationNotifier(ref.read(dioClientProvider)),
);

class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier(this._dio) : super(const NotificationState()) {
    load();
  }

  final Dio _dio;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final Response<Map<String, dynamic>> res =
          await _loadNotificationsResponse();
      final List<dynamic> raw = _readNotificationsList(res.data);
      state = state.copyWith(
        isLoading: false,
        notifications: raw
            .map((dynamic e) =>
                NotificationDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        unreadCount: _readUnreadCount(res.data, raw),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> markRead(String notificationId) async {
    try {
      await _dio.patch<void>(
          '/api/v1/notifications/$notificationId/read');
      state = state.copyWith(
        notifications: state.notifications.map((NotificationDto n) {
          return n.notificationId == notificationId
              ? NotificationDto(
                  notificationId: n.notificationId,
                  title: n.title,
                  body: n.body,
                  type: n.type,
                  isRead: true,
                  createdAt: n.createdAt,
                  data: n.data,
                )
              : n;
        }).toList(),
        unreadCount: (state.unreadCount - 1).clamp(0, state.unreadCount),
      );
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      try {
        await _dio.patch<void>('/api/v1/notifications/read-all');
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) {
          rethrow;
        }
        await _dio.post<void>('/api/v1/notifications/me/mark-all-read');
      }
      state = state.copyWith(
        notifications: state.notifications.map((NotificationDto n) {
          return NotificationDto(
            notificationId: n.notificationId,
            title: n.title,
            body: n.body,
            type: n.type,
            isRead: true,
            createdAt: n.createdAt,
            data: n.data,
          );
        }).toList(),
        unreadCount: 0,
      );
    } catch (_) {}
  }

  Future<Response<Map<String, dynamic>>> _loadNotificationsResponse() async {
    try {
      return await _dio.get<Map<String, dynamic>>('/api/v1/notifications');
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) {
        rethrow;
      }
    }

    return _dio.get<Map<String, dynamic>>('/api/v1/notifications/me');
  }

  List<dynamic> _readNotificationsList(Map<String, dynamic>? data) {
    if (data == null) {
      return const <dynamic>[];
    }

    final Object? primary = data['notifications'];
    if (primary is List<dynamic>) {
      return primary;
    }

    final Object? wrapped = data['data'];
    if (wrapped is List<dynamic>) {
      return wrapped;
    }

    return const <dynamic>[];
  }

  int _readUnreadCount(Map<String, dynamic>? data, List<dynamic> raw) {
    if (data == null) {
      return 0;
    }

    final Object? explicit = data['unread'];
    if (explicit is int) {
      return explicit;
    }
    if (explicit is num) {
      return explicit.toInt();
    }

    return raw.where((dynamic item) {
      if (item is! Map<String, dynamic>) {
        return false;
      }
      return item['is_read'] == false || item['read'] == false;
    }).length;
  }
}
