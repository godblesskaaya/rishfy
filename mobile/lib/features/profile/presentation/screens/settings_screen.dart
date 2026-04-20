import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/locale_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          SwitchListTile(
            title: const Text('Language'),
            subtitle: Text(locale.languageCode == 'en' ? 'English' : 'Kiswahili'),
            value: locale.languageCode == 'sw',
            onChanged: (bool _) => ref.read(localeProvider.notifier).toggle(),
          ),
          const ListTile(title: Text('Notifications')),
          const ListTile(title: Text('Biometric lock')),
          const ListTile(title: Text('Privacy policy')),
          const ListTile(title: Text('Terms of service')),
          const AboutListTile(
            applicationName: 'Rishfy',
            applicationVersion: '0.1.0',
            icon: Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }
}
