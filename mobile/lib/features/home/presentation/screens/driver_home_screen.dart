import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/providers/active_role_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../bookings/presentation/providers/booking_provider.dart';
import '../../../routes/domain/entities/route_entity.dart';
import '../../../routes/presentation/providers/route_provider.dart';

class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? firstName = ref.watch(currentUserProvider)?.firstName;
    final double? rating = ref.watch(currentUserProvider)?.ratingAverage;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AsyncValue<List<RouteEntity>> routesAsync =
        ref.watch(myRoutesProvider);
    final AsyncValue<DriverEarningsStats> statsAsync =
        ref.watch(driverEarningsStatsProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header with role toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Habari, ${firstName ?? ''}',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ready to earn today?',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => context.push('/notifications'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Role switch
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _RoleButton(
                        label: 'Passenger',
                        selected: false,
                        onTap: () {
                          unawaited(
                            ref
                                .read(activeRoleProvider.notifier)
                                .setRole('passenger'),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _RoleButton(
                        label: 'Driver',
                        selected: true,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ),

              // Earnings card — real numbers from completed bookings.
              _EarningsCard(
                statsAsync: statsAsync,
                rating: rating,
                onRetry: () => ref.invalidate(myDriverBookingsProvider),
              ),
              const SizedBox(height: 24),

              // Post a route CTA
              ElevatedButton.icon(
                onPressed: () => context.push('/routes/post'),
                icon: const Icon(Icons.add_road),
                label: const Text('Post a new route'),
              ),
              const SizedBox(height: 24),

              // Active routes
              Row(
                children: <Widget>[
                  Text(
                    'Your posted routes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh',
                    onPressed: () => ref.invalidate(myRoutesProvider),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PostedRoutesSection(routesAsync: routesAsync),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animationFast,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : null,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({
    required this.statsAsync,
    required this.rating,
    required this.onRetry,
  });

  final AsyncValue<DriverEarningsStats> statsAsync;
  final double? rating;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String formattedTotal = statsAsync.maybeWhen(
      data: (DriverEarningsStats s) =>
          'TZS ${NumberFormat('#,###').format(s.weekTotalTzs)}',
      orElse: () => '—',
    );
    final int trips = statsAsync.maybeWhen(
      data: (DriverEarningsStats s) => s.weekTrips,
      orElse: () => 0,
    );
    final String ratingLabel = (rating == null || rating == 0)
        ? '—'
        : rating!.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary,
            scheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'This week',
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (statsAsync.hasError)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.refresh, color: scheme.onPrimary),
                  onPressed: onRetry,
                ),
            ],
          ),
          const SizedBox(height: 8),
          statsAsync.isLoading
              ? SizedBox(
                  height: 32,
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: scheme.onPrimary,
                          strokeWidth: 2,
                        ),
                      ),
                    ],
                  ),
                )
              : Text(
                  formattedTotal,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _Stat(
                label: 'Trips',
                value: '$trips',
                color: scheme.onPrimary,
              ),
              const SizedBox(width: 32),
              _Stat(
                label: 'Rating',
                value: ratingLabel,
                color: scheme.onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _PostedRoutesSection extends StatelessWidget {
  const _PostedRoutesSection({required this.routesAsync});

  final AsyncValue<List<RouteEntity>> routesAsync;

  String _messageFromError(Object error) {
    if (error is AppException) return error.message;
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Widget emptyBox(String title, String? subtitle) => Container(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            children: <Widget>[
              Icon(Icons.route, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        );

    return routesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, __) => emptyBox(
        'Could not load your routes',
        _messageFromError(error),
      ),
      data: (List<RouteEntity> routes) {
        if (routes.isEmpty) {
          return emptyBox(
            'No active routes',
            'Post your commute to start earning.',
          );
        }
        return Column(
          children: routes
              .map((RouteEntity r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PostedRouteCard(route: r),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _PostedRouteCard extends StatelessWidget {
  const _PostedRouteCard({required this.route});

  final RouteEntity route;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      onTap: () => context.push('/routes/${route.routeId}'),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${route.originName} → ${route.destinationName}',
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  DateFormat('EEE d MMM, HH:mm')
                      .format(route.departureDatetime.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                Icon(Icons.event_seat, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${route.availableSeats}/${route.totalSeats}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
