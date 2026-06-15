import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../routes/data/models/route_models.dart';
import '../../domain/public_driver_profile.dart';
import '../providers/profile_provider.dart';

class PublicDriverProfileScreen extends ConsumerWidget {
  const PublicDriverProfileScreen({required this.driverId, super.key});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PublicDriverProfile> driverAsync =
        ref.watch(publicDriverProvider(driverId));
    final FavoriteDriverActionState favoriteState =
        ref.watch(favoriteDriverActionProvider);
    final BlockedUserActionState blockState = ref.watch(blockedUserActionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Driver profile')),
      body: driverAsync.when(
        loading: () => const LoadingView(message: 'Loading driver profile'),
        error: (Object error, _) => ErrorView.fromException(
          error,
          onRetry: () => ref.invalidate(publicDriverProvider(driverId)),
        ),
        data: (PublicDriverProfile profile) {
          final User driver = profile.user;
          return ListView(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            children: <Widget>[
              _DriverHeader(driver: driver),
              const SizedBox(height: 16),
              _TrustSummary(profile: profile),
              if (profile.activeVehicle != null) ...<Widget>[
                const SizedBox(height: 16),
                _VehicleSummary(vehicle: profile.activeVehicle!),
              ],
              if (profile.reviews.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _ReviewSummary(reviews: profile.reviews),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed:
                    favoriteState.status == FavoriteDriverActionStatus.loading
                        ? null
                        : () => _saveDriver(context, ref),
                icon: const Icon(Icons.favorite_border),
                label: const Text('Save driver'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: blockState.status == BlockedUserActionStatus.loading
                    ? null
                    : () => _confirmBlock(context, ref, driver),
                icon: const Icon(Icons.block),
                label: const Text('Block driver'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveDriver(BuildContext context, WidgetRef ref) async {
    await ref.read(favoriteDriverActionProvider.notifier).add(driverId);
    final FavoriteDriverActionState state = ref.read(favoriteDriverActionProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.status == FavoriteDriverActionStatus.success
              ? 'Driver saved to favorites.'
              : state.error ?? 'Could not save driver.',
        ),
      ),
    );
  }

  Future<void> _confirmBlock(
    BuildContext context,
    WidgetRef ref,
    User driver,
  ) async {
    final TextEditingController reasonCtrl = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Block driver?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('${driver.fullName} will not be intentionally matched with you.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonCtrl.text.trim()),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null) return;

    await ref.read(blockedUserActionProvider.notifier).block(
          driverId,
          reason: reason.isEmpty ? null : reason,
        );
    final BlockedUserActionState state = ref.read(blockedUserActionProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.status == BlockedUserActionStatus.success
              ? 'Driver blocked.'
              : state.error ?? 'Could not block driver.',
        ),
      ),
    );
  }
}

class _DriverHeader extends StatelessWidget {
  const _DriverHeader({required this.driver});

  final User driver;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 34,
            backgroundColor: scheme.primary,
            child: Text(
              driver.initials.isEmpty ? '?' : driver.initials,
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  driver.fullName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  driver.isVerified ? 'Verified driver' : 'Driver profile',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustSummary extends StatelessWidget {
  const _TrustSummary({required this.profile});

  final PublicDriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final User driver = profile.user;
    final String rating = driver.ratingCount > 0
        ? '${driver.ratingAverage.toStringAsFixed(1)} / 5.0'
        : 'No rating yet';
    final bool verified = profile.driverProfile?.isVerified ?? driver.isVerified;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          children: <Widget>[
            _ProfileMetric(
              icon: Icons.star_border,
              label: 'Rating',
              value: rating,
            ),
            const Divider(),
            _ProfileMetric(
              icon: Icons.reviews_outlined,
              label: 'Reviews',
              value: '${driver.ratingCount}',
            ),
            const Divider(),
            _ProfileMetric(
              icon: Icons.verified_user_outlined,
              label: 'Verification',
              value: verified ? 'Verified' : 'Pending',
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleSummary extends StatelessWidget {
  const _VehicleSummary({required this.vehicle});

  final DriverVehicleOption vehicle;

  @override
  Widget build(BuildContext context) {
    final List<String> details = <String>[
      if ((vehicle.color ?? '').isNotEmpty) vehicle.color!,
      if (vehicle.year != null && vehicle.year! > 0) '${vehicle.year}',
      if (vehicle.capacity != null && vehicle.capacity! > 0)
        '${vehicle.capacity} seats',
    ];
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.directions_car_outlined),
        title: Text(vehicle.label),
        subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.reviews});

  final List<DriverReview> reviews;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Recent reviews',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ...reviews.take(3).map(
                  (DriverReview review) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.star,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            review.comment?.isNotEmpty ?? false
                                ? '${review.score}/5 · ${review.comment}'
                                : '${review.score}/5',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
