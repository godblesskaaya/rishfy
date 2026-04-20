import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    // Wait for auth controller to finish its initial build
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final AsyncValue<AuthState> auth = ref.read(authControllerProvider);
    auth.when(
      data: (AuthState state) {
        if (state.isAuthenticated) {
          context.go('/home');
        } else {
          context.go('/login');
        }
      },
      loading: () {
        // Try again shortly
        Future<void>.delayed(const Duration(milliseconds: 300), _decide);
      },
      error: (_, __) => context.go('/login'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: scheme.onPrimary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.directions_car_rounded,
                size: 72,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Rishfy',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share the ride, share the cost',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                  ),
            ),
            const SizedBox(height: 48),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
