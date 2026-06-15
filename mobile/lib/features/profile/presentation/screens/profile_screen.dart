import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final bool isDriver = user?.role == UserRole.driver;
    final String vehicleTitle =
        isDriver ? 'My vehicles' : 'Become a driver & vehicles';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                CircleAvatar(
                  radius: 48,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    user?.initials ?? '?',
                    style: TextStyle(
                      fontSize: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(user?.fullName ?? '',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  user?.phoneNumber ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Edit profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/edit'),
          ),
          ListTile(
            leading: const Icon(Icons.directions_car_outlined),
            title: Text(vehicleTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/vehicles'),
          ),
          ListTile(
            leading: const Icon(Icons.emergency_outlined),
            title: const Text('Emergency contacts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/emergency-contacts'),
          ),
          ListTile(
            leading: const Icon(Icons.payment),
            title: const Text('Payment methods'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/payment-methods'),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Favorite drivers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/favorite-drivers'),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Blocked users'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/blocked-users'),
          ),
          ListTile(
            leading: const Icon(Icons.report_problem_outlined),
            title: const Text('Safety reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/safety-reports'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/help'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(
              'Log out',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
