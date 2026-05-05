import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../shared/providers/locale_provider.dart';

class ShellScreen extends ConsumerWidget {
  const ShellScreen({required this.child, super.key});

  final Widget child;

  static const List<_Tab> _passengerTabs = <_Tab>[
    _Tab(path: '/home', icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _Tab(path: '/search', icon: Icons.search, activeIcon: Icons.search, label: 'Search'),
    _Tab(path: '/bookings', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Bookings'),
    _Tab(path: '/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  static const List<_Tab> _driverTabs = <_Tab>[
    _Tab(path: '/home', icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _Tab(path: '/bookings', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Trips'),
    _Tab(path: '/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  int _indexOf(String location, List<_Tab> tabs) {
    for (int i = 0; i < tabs.length; i++) {
      if (location.startsWith(tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String location = GoRouterState.of(context).matchedLocation;
    final AsyncValue<AuthState> auth = ref.watch(authControllerProvider);
    final String role = ref.watch(activeRoleProvider);
    final List<_Tab> tabs = role == 'driver' ? _driverTabs : _passengerTabs;
    final int currentIndex = _indexOf(location, tabs);

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
            onTap: (int i) => context.go(tabs[i].path),
            items: tabs.map((_Tab t) {
              final bool active = tabs[currentIndex] == t;
              return BottomNavigationBarItem(
                icon: Icon(active ? t.activeIcon : t.icon),
                label: t.label,
              );
            }).toList(),
          ),
          floatingActionButton: role == 'driver'
              ? _EmergencyFab(onTap: () => _showEmergencyDialog(context))
              : null,
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

  Future<void> _showEmergencyDialog(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Emergency Alert'),
        content: const Text(
          'Send an emergency alert to Rishfy dispatch and your emergency contacts?',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send Alert', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency alert sent. Stay safe.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
}

/// Long-press to trigger emergency. Circular progress fill prevents accidental taps.
class _EmergencyFab extends StatefulWidget {
  const _EmergencyFab({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_EmergencyFab> createState() => _EmergencyFabState();
}

class _EmergencyFabState extends State<_EmergencyFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addStatusListener((AnimationStatus s) {
        if (s == AnimationStatus.completed && _isHolding) {
          widget.onTap();
          _controller.reset();
          setState(() => _isHolding = false);
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) {
        setState(() => _isHolding = true);
        _controller.forward();
      },
      onLongPressEnd: (_) {
        if (_isHolding) {
          _controller.reset();
          setState(() => _isHolding = false);
        }
      },
      child: Tooltip(
        message: 'Hold for emergency',
        child: FloatingActionButton(
          heroTag: 'emergency_fab',
          backgroundColor: Colors.red,
          onPressed: null,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext ctx, Widget? child) {
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  if (_isHolding)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: _controller.value,
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  const Icon(Icons.emergency, color: Colors.white),
                ],
              );
            },
          ),
        ),
      ),
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
