import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../shared/widgets/async_views.dart';
import '../../data/models/notification_models.dart';
import '../providers/notification_preferences_provider.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _iconForType(String type) {
    switch (type) {
      case 'booking_confirmed': return Icons.check_circle;
      case 'booking_cancelled': return Icons.cancel;
      case 'trip_started': return Icons.directions_car;
      case 'trip_completed': return Icons.flag;
      case 'payment_confirmed': return Icons.payments;
      case 'payment_failed': return Icons.payment;
      default: return Icons.notifications;
    }
  }

  void _handleNotificationTap(BuildContext ctx, NotificationDto n) {
    final Map<String, dynamic>? data = n.data;
    String? readString(List<String> keys) {
      if (data == null) return null;
      for (final String key in keys) {
        final Object? value = data[key];
        if (value is String && value.isNotEmpty) return value;
        if (value is num) return value.toString();
      }
      return null;
    }

    // Trip events take precedence — they're time-sensitive.
    if (n.type == 'trip_started' || n.type == 'trip_completed') {
      final String? bookingId =
          readString(<String>['booking_id', 'bookingId', 'trip_id', 'tripId']);
      if (bookingId != null) {
        ctx.push(
          n.type == 'trip_started'
              ? '/trip/$bookingId'
              : '/bookings/$bookingId',
        );
        return;
      }
    }

    final String? bookingId =
        readString(<String>['booking_id', 'bookingId']);
    if (bookingId != null) {
      ctx.push('/bookings/$bookingId');
      return;
    }

    final String? routeId = readString(<String>['route_id', 'routeId']);
    if (routeId != null) {
      ctx.push('/routes/$routeId');
    }
  }

  Color _colorForType(String type, BuildContext ctx) {
    if (type.contains('failed') || type.contains('cancel')) {
      return Theme.of(ctx).colorScheme.error;
    }
    if (type.contains('confirm') || type.contains('complete')) {
      return Colors.green;
    }
    return Theme.of(ctx).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotificationState state = ref.watch(notificationProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            const Text('Notifications'),
            if (state.unreadCount > 0) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${state.unreadCount}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 12)),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref.read(notificationProvider.notifier).markAllRead(),
              child: const Text('Mark all read'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(notificationProvider.notifier).load(),
          ),
        ],
      ),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, NotificationState state) {
    final NotificationPreferences prefs =
        ref.watch(notificationPreferencesProvider);
    final List<NotificationDto> visible = state.notifications
        .where((NotificationDto n) =>
            prefs.isEnabled(categoryFor(n.type)) ||
            categoryFor(n.type) == NotificationCategory.system)
        .toList();
    if (state.isLoading && visible.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && visible.isEmpty) {
      return ErrorView(
        message: state.error!,
        onRetry: () => ref.read(notificationProvider.notifier).load(),
      );
    }
    if (visible.isEmpty) {
      return const EmptyView(
        icon: Icons.notifications_none,
        title: 'No notifications yet',
        subtitle: "We'll notify you about bookings, trips, and more",
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(notificationProvider.notifier).load(),
      child: ListView.separated(
        itemCount: visible.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (BuildContext ctx, int i) {
          final NotificationDto n = visible[i];
          return _NotificationTile(
            notification: n,
            icon: _iconForType(n.type),
            iconColor: _colorForType(n.type, ctx),
            onTap: () {
              if (!n.isRead) {
                ref.read(notificationProvider.notifier).markRead(n.notificationId);
              }
              _handleNotificationTap(ctx, n);
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final NotificationDto notification;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool unread = !notification.isRead;
    return ListTile(
      tileColor: unread
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.15),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(notification.title,
          style: TextStyle(
              fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(notification.body),
          const SizedBox(height: 2),
          Text(timeago.format(notification.createdAt),
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      trailing: unread
          ? Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
