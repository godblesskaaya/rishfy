import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_preferences_provider.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NotificationPreferences prefs =
        ref.watch(notificationPreferencesProvider);
    final NotificationPreferencesNotifier notifier =
        ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Pick what shows up in your notifications list and as a push '
              'alert. Critical safety messages always come through.',
            ),
          ),
          for (final NotificationCategory c in NotificationCategory.values)
            SwitchListTile(
              title: Text(c.label),
              subtitle: Text(c.description),
              value: prefs.isEnabled(c),
              onChanged: (bool v) => notifier.setEnabled(c, v),
            ),
        ],
      ),
    );
  }
}
