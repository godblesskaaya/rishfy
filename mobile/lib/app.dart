import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/biometric_lock_provider.dart';
import 'shared/providers/locale_provider.dart';

class RishfyApp extends ConsumerStatefulWidget {
  const RishfyApp({super.key});

  @override
  ConsumerState<RishfyApp> createState() => _RishfyAppState();
}

class _RishfyAppState extends ConsumerState<RishfyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock when the app goes to background (so it requires biometric on
    // next resume). Only locks if user has enabled the feature.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(biometricLockProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Rishfy',
      debugShowCheckedModeBanner: false,

      // Theme
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,

      // Localization
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Routing (go_router handles all navigation)
      routerConfig: router,

      builder: (BuildContext context, Widget? child) {
        // Enforce app-wide text scale clamping to avoid layout breakage
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: Stack(
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              const _BiometricLockOverlay(),
            ],
          ),
        );
      },
    );
  }
}

class _BiometricLockOverlay extends ConsumerStatefulWidget {
  const _BiometricLockOverlay();

  @override
  ConsumerState<_BiometricLockOverlay> createState() =>
      _BiometricLockOverlayState();
}

class _BiometricLockOverlayState
    extends ConsumerState<_BiometricLockOverlay> {
  bool _prompting = false;

  Future<void> _maybeAutoUnlock(BiometricLockState lock) async {
    if (_prompting || !lock.enabled || !lock.locked) return;
    _prompting = true;
    await ref.read(biometricLockProvider.notifier).unlock();
    _prompting = false;
  }

  @override
  Widget build(BuildContext context) {
    final BiometricLockState lock = ref.watch(biometricLockProvider);
    if (!lock.enabled || !lock.locked) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoUnlock(lock));
    return Positioned.fill(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.lock_outline,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rishfy is locked',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use biometric authentication to continue.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(biometricLockProvider.notifier).unlock(),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
