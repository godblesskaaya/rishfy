import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

/// The shell wraps the main tab screens (Home / Search / Bookings / Profile)
/// and provides the bottom navigation.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({required this.child, super.key});

  final Widget child;

  static const List<_Tab> _tabs = <_Tab>[
    _Tab(path: '/home', icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _Tab(path: '/search', icon: Icons.search, activeIcon: Icons.search, label: 'Search'),
    _Tab(path: '/bookings', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Bookings'),
    _Tab(path: '/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  int _indexOf(String location) {
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String location = GoRouterState.of(context).matchedLocation;
    final int currentIndex = _indexOf(location);
    final AsyncValue<AuthState> auth = ref.watch(authControllerProvider);

    // Defensive: if somehow landed here unauthenticated, bounce to login.
    return auth.when(
      data: (AuthState state) {
        if (!state.isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.go('/login');
          });
          return const SizedBox.shrink();
        }
        return Scaffold(
          body: child,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: (int i) => context.go(_tabs[i].path),
            items: _tabs.map((_Tab t) {
              final bool active = _tabs[currentIndex] == t;
              return BottomNavigationBarItem(
                icon: Icon(active ? t.activeIcon : t.icon),
                label: t.label,
              );
            }).toList(),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.go('/login');
        });
        return const SizedBox.shrink();
      },
    );
  }
}

class _Tab {
  const _Tab({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
