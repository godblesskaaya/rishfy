import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/async_views.dart';

/// Wire up in Sprint 4 with notification-service GetNotificationHistory.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const EmptyView(
        icon: Icons.notifications_none,
        title: 'No notifications yet',
        subtitle: "We'll notify you about bookings, trips, and more",
      ),
    );
  }
}
