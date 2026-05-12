import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/providers/locale_provider.dart';
import '../../../auth/presentation/providers/biometric_lock_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale locale = ref.watch(localeProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final BiometricLockState lock = ref.watch(biometricLockProvider);

    String themeLabel(ThemeMode mode) {
      switch (mode) {
        case ThemeMode.system:
          return 'Match system';
        case ThemeMode.light:
          return 'Light';
        case ThemeMode.dark:
          return 'Dark';
      }
    }

    Future<void> pickThemeMode() async {
      final ThemeMode? picked = await showModalBottomSheet<ThemeMode>(
        context: context,
        builder: (BuildContext ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final ThemeMode mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    title: Text(themeLabel(mode)),
                    value: mode,
                    groupValue: themeMode,
                    onChanged: (ThemeMode? v) => Navigator.of(ctx).pop(v),
                  ),
              ],
            ),
          );
        },
      );
      if (picked != null) {
        await ref.read(themeModeProvider.notifier).setMode(picked);
      }
    }

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
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Appearance'),
            subtitle: Text(themeLabel(themeMode)),
            onTap: pickThemeMode,
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Choose which alerts you receive'),
            onTap: () => context.push('/notifications/preferences'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric lock'),
            subtitle: Text(
              !lock.available
                  ? 'No biometric hardware enrolled on this device'
                  : lock.enabled
                      ? 'Unlock Rishfy with your fingerprint or face'
                      : 'Require biometric auth to open the app',
            ),
            value: lock.enabled,
            onChanged: !lock.available
                ? null
                : (bool v) async {
                    final BiometricLockNotifier n =
                        ref.read(biometricLockProvider.notifier);
                    final bool ok = v ? await n.enable() : await n.disable();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Biometric verification did not succeed.'),
                        ),
                      );
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => context.push('/legal/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of service'),
            onTap: () => context.push('/legal/terms'),
          ),
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
