import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/models/notification_models.dart';

String? _readPayloadString(
  Map<String, dynamic>? data,
  List<String> keys,
) {
  if (data == null) {
    return null;
  }
  for (final String key in keys) {
    final Object? value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num) {
      return value.toString();
    }
  }
  return null;
}

String? notificationRouteFor({
  required String type,
  Map<String, dynamic>? data,
}) {
  final String normalizedType = type.trim().toLowerCase().replaceAll('.', '_');
  final String? explicitPath = _readPayloadString(
    data,
    <String>['path', 'route', 'destination', 'deeplink'],
  );
  if (explicitPath != null && explicitPath.startsWith('/')) {
    return explicitPath;
  }

  final bool payoutNotification = normalizedType.contains('payout') ||
      normalizedType.contains('settlement') ||
      normalizedType.contains('wallet') ||
      normalizedType.contains('earnings');
  final String? payoutId = _readPayloadString(
    data,
    payoutNotification
        ? <String>[
            'payout_id',
            'payoutId',
            'settlement_id',
            'settlementId',
            'entity_id',
            'entityId',
          ]
        : <String>['payout_id', 'payoutId', 'settlement_id', 'settlementId'],
  );
  if (payoutId != null) {
    return '/driver/payouts/$payoutId';
  }
  if (payoutNotification) {
    return '/driver/payouts';
  }

  final String? bookingId = _readPayloadString(
    data,
    <String>['booking_id', 'bookingId', 'entity_id', 'entityId'],
  );
  final String? journeyState = _readPayloadString(
    data,
    <String>['journey_state', 'journeyState', 'state'],
  )?.toLowerCase();
  final bool liveTripPreferred = const <String>{
        'walking_to_pickup',
        'waiting_for_driver',
        'driver_approaching',
        'driver_arrived',
        'boarded',
        'in_transit',
        'approaching_dropoff',
        'dropped_off',
        'walking_to_destination',
      }.contains(journeyState) ||
      normalizedType.startsWith('trip_') ||
      normalizedType.contains('arrived') ||
      normalizedType.contains('approach') ||
      normalizedType.contains('boarded') ||
      normalizedType.contains('dropoff') ||
      normalizedType.contains('walking');
  final bool receiptPreferred = normalizedType.contains('receipt') ||
      normalizedType.contains('refund') ||
      normalizedType.contains('payment_confirmed') ||
      normalizedType.contains('payment_completed');

  if (bookingId != null) {
    if (liveTripPreferred) {
      return '/trip/$bookingId';
    }
    if (receiptPreferred) {
      return '/bookings/$bookingId/receipt';
    }
    return '/bookings/$bookingId';
  }

  final String? routeId = _readPayloadString(
    data,
    <String>['route_id', 'routeId'],
  );
  if (routeId != null) {
    return '/routes/$routeId';
  }

  if (normalizedType.contains('favorite_driver') ||
      normalizedType.contains('favourite_driver')) {
    return '/profile/favorite-drivers';
  }

  if (normalizedType.contains('safety')) {
    return '/profile/safety-reports';
  }

  if (normalizedType.contains('block') ||
      normalizedType.contains('moderation')) {
    return '/profile/blocked-users';
  }

  if (normalizedType.contains('payment_method')) {
    return '/profile/payment-methods';
  }

  if (normalizedType.contains('support') || normalizedType.contains('help')) {
    return '/help';
  }

  return null;
}

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
    unawaited(load());
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
      await _dio.patch<void>('/api/v1/notifications/$notificationId/read');
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

class NotificationPrompt {
  const NotificationPrompt({
    required this.id,
    required this.title,
    required this.body,
    required this.route,
  });

  final String id;
  final String title;
  final String body;
  final String route;
}

class NotificationInteractionState {
  const NotificationInteractionState({
    this.pendingRoute,
    this.foregroundPrompt,
  });

  final String? pendingRoute;
  final NotificationPrompt? foregroundPrompt;

  NotificationInteractionState copyWith({
    String? pendingRoute,
    NotificationPrompt? foregroundPrompt,
    bool clearPendingRoute = false,
    bool clearForegroundPrompt = false,
  }) =>
      NotificationInteractionState(
        pendingRoute:
            clearPendingRoute ? null : pendingRoute ?? this.pendingRoute,
        foregroundPrompt: clearForegroundPrompt
            ? null
            : foregroundPrompt ?? this.foregroundPrompt,
      );
}

final StateNotifierProvider<NotificationInteractionNotifier,
        NotificationInteractionState> notificationInteractionProvider =
    StateNotifierProvider<NotificationInteractionNotifier,
        NotificationInteractionState>(
  (Ref ref) => NotificationInteractionNotifier(ref),
);

class NotificationInteractionNotifier
    extends StateNotifier<NotificationInteractionState> {
  NotificationInteractionNotifier(this._ref)
      : super(const NotificationInteractionState()) {
    unawaited(_initialize());
  }

  final Ref _ref;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  Future<void> _initialize() async {
    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_handleForeground);
    _openedAppSub ??=
        FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedApp);

    final RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedApp(initialMessage);
    }
  }

  void _handleForeground(RemoteMessage message) {
    unawaited(_ref.read(notificationProvider.notifier).load());
    final String? route = notificationRouteFor(
      type: _messageType(message),
      data: message.data,
    );
    if (route == null) {
      return;
    }

    state = state.copyWith(
      foregroundPrompt: NotificationPrompt(
        id: _messageId(message),
        title: message.notification?.title ?? 'Trip update',
        body: message.notification?.body ?? 'Open the latest journey update.',
        route: route,
      ),
    );
  }

  void _handleOpenedApp(RemoteMessage message) {
    unawaited(_ref.read(notificationProvider.notifier).load());
    final String? route = notificationRouteFor(
      type: _messageType(message),
      data: message.data,
    );
    if (route == null) {
      return;
    }

    state = state.copyWith(pendingRoute: route);
  }

  String _messageType(RemoteMessage message) {
    final String? type = message.data['type']?.toString() ??
        message.data['event_type']?.toString() ??
        message.data['template_key']?.toString();
    return (type == null || type.trim().isEmpty) ? 'info' : type;
  }

  String _messageId(RemoteMessage message) =>
      message.messageId ??
      message.sentTime?.toIso8601String() ??
      DateTime.now().toIso8601String();

  void clearPendingRoute() {
    state = state.copyWith(clearPendingRoute: true);
  }

  void clearForegroundPrompt() {
    state = state.copyWith(clearForegroundPrompt: true);
  }

  @override
  void dispose() {
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedAppSub?.cancel());
    super.dispose();
  }
}
