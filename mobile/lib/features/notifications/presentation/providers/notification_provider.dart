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
          await _dio.get<Map<String, dynamic>>('/api/v1/notifications');
      final List<dynamic> raw =
          res.data?['notifications'] as List<dynamic>? ?? <dynamic>[];
      state = state.copyWith(
        isLoading: false,
        notifications: raw
            .map((dynamic e) =>
                NotificationDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        unreadCount: res.data?['unread'] as int? ?? 0,
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
      await _dio.patch<void>('/api/v1/notifications/read-all');
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
}
