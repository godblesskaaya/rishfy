import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../shared/providers/active_role_provider.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/domain/emergency_contact.dart';
import '../../../profile/presentation/providers/emergency_contacts_provider.dart';

class ShellScreen extends ConsumerWidget {
  const ShellScreen({required this.child, super.key});

  final Widget child;

  List<_Tab> _passengerTabs(AppLocalizations l) => <_Tab>[
        _Tab(path: '/home', icon: Icons.home_outlined, activeIcon: Icons.home, label: l.t('home')),
        _Tab(path: '/search', icon: Icons.search, activeIcon: Icons.search, label: l.t('search')),
        _Tab(path: '/bookings', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: l.t('bookings')),
        _Tab(path: '/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: l.t('profile')),
      ];

  List<_Tab> _driverTabs(AppLocalizations l) => <_Tab>[
        _Tab(path: '/home', icon: Icons.home_outlined, activeIcon: Icons.home, label: l.t('home')),
        _Tab(path: '/bookings', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: l.locale.languageCode == 'sw' ? 'Safari' : 'Trips'),
        _Tab(path: '/profile', icon: Icons.person_outline, activeIcon: Icons.person, label: l.t('profile')),
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
    final AppLocalizations l = AppLocalizations.of(context);

    return auth.when(
      data: (AuthState state) {
        if (!state.isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.go('/login');
          });
          return const SizedBox.shrink();
        }
        final bool showDriverTabs =
            state.user?.role == UserRole.driver && role == 'driver';
        final List<_Tab> tabs =
            showDriverTabs ? _driverTabs(l) : _passengerTabs(l);
        final int currentIndex = _indexOf(location, tabs);
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
          floatingActionButton: showDriverTabs
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
    await showEmergencyDialog(context);
  }
}

const String kTanzaniaEmergencyNumber = '112';

/// Shows an emergency dialog with the national emergency number plus any
/// saved emergency contacts. All numbers are tap-to-copy.
Future<void> showEmergencyDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => const _EmergencyDialog(),
  );
}

class _EmergencyDialog extends ConsumerWidget {
  const _EmergencyDialog();

  Future<void> _copy(BuildContext ctx, String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Copied $number')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<EmergencyContact> contacts =
        ref.watch(emergencyContactsProvider);
    return AlertDialog(
      title: const Text('Need help right now?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'For an immediate emergency in Tanzania, dial the national '
              'emergency line.',
            ),
            const SizedBox(height: 16),
            _EmergencyRow(
              label: 'Emergency services',
              number: kTanzaniaEmergencyNumber,
              highlight: true,
              onCopy: () => _copy(context, kTanzaniaEmergencyNumber),
            ),
            if (contacts.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              const Text(
                'Your emergency contacts',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ...contacts.map(
                (EmergencyContact c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _EmergencyRow(
                    label: c.name,
                    number: c.phone,
                    onCopy: () => _copy(context, c.phone),
                  ),
                ),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Tip: add trusted contacts under Profile → Emergency contacts '
                'to see them here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({
    required this.label,
    required this.number,
    required this.onCopy,
    this.highlight = false,
  });

  final String label;
  final String number;
  final VoidCallback onCopy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.red.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.local_phone,
              color: highlight ? Colors.red : null, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  number,
                  style: TextStyle(
                    color: highlight ? Colors.red : null,
                    fontWeight: highlight ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: onCopy,
          ),
        ],
      ),
    );
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
