import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/providers/active_role_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../bookings/domain/entities/booking_entity.dart';
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
    final AsyncValue<BookingEntity?> activeJourneyAsync =
        ref.watch(activeDriverJourneyProvider);

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
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
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

              Text(
                'Active driving task',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _DriverJourneyCard(
                activeJourneyAsync: activeJourneyAsync,
                routesAsync: routesAsync,
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

class _DriverJourneyCard extends StatelessWidget {
  const _DriverJourneyCard({
    required this.activeJourneyAsync,
    required this.routesAsync,
  });

  final AsyncValue<BookingEntity?> activeJourneyAsync;
  final AsyncValue<List<RouteEntity>> routesAsync;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Widget placeholder({
      required IconData icon,
      required String title,
      required String subtitle,
    }) {
      return Container(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return activeJourneyAsync.when(
      loading: () => placeholder(
        icon: Icons.sync,
        title: 'Checking active driving task',
        subtitle: 'We are loading the next trip you need to operate.',
      ),
      error: (Object error, _) => placeholder(
        icon: Icons.error_outline,
        title: 'Could not load driving task',
        subtitle: error.toString(),
      ),
      data: (BookingEntity? booking) {
        if (booking == null) {
          final RouteEntity? nextRoute = routesAsync.maybeWhen(
            data: (List<RouteEntity> routes) {
              final List<RouteEntity> eligible = routes
                  .where((RouteEntity route) =>
                      route.status != 'cancelled' &&
                      route.departureDatetime.isAfter(
                        DateTime.now().subtract(const Duration(hours: 1)),
                      ))
                  .toList()
                ..sort(
                  (RouteEntity a, RouteEntity b) =>
                      a.departureDatetime.compareTo(b.departureDatetime),
                );
              return eligible.isEmpty ? null : eligible.first;
            },
            orElse: () => null,
          );

          if (nextRoute == null) {
            return placeholder(
              icon: Icons.route,
              title: 'No active driving task',
              subtitle:
                  'Confirmed pickup and live drop-off work will appear here.',
            );
          }

          return InkWell(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            onTap: () =>
                unawaited(context.push('/routes/${nextRoute.routeId}')),
            child: Container(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                gradient: LinearGradient(
                  colors: <Color>[
                    scheme.tertiaryContainer,
                    scheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.alt_route, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Next route operation',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${nextRoute.originName} -> ${nextRoute.destinationName}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Departure ${DateFormat('d MMM | HH:mm').format(nextRoute.departureDatetime.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${nextRoute.availableSeats}/${nextRoute.totalSeats} seats open • ${nextRoute.vehiclePlate}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No rider is currently driving your live workspace. Open the route to manage departures and route details.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          );
        }

        final String nextAction = booking.nextDriverActionLabel;
        final String focusLabel = booking.nextStopLabel;
        final int? eta =
            booking.etaToPickupSeconds ?? booking.etaToDropoffSeconds;
        final String stopLabel =
            booking.isPrePickupJourney ? 'Pickup stop' : 'Drop-off stop';
        final String taskTitle = _driverTaskTitle(booking);
        final String taskSubtitle = _driverTaskSubtitle(booking);

        return InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          onTap: () => unawaited(context.push('/trip/${booking.bookingId}')),
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              gradient: LinearGradient(
                colors: <Color>[
                  scheme.secondaryContainer,
                  scheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.directions_car_filled, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        taskTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${booking.originName ?? 'Route'} -> '
                  '${booking.destinationName ?? ''}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  taskSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _JourneyBadge(
                      icon: Icons.person_outline,
                      label: 'Rider',
                      value: booking.passengerDisplayName,
                    ),
                    _JourneyBadge(
                      icon: booking.isPrePickupJourney
                          ? Icons.place_outlined
                          : Icons.flag_outlined,
                      label: stopLabel,
                      value: focusLabel,
                    ),
                    if (eta != null)
                      _JourneyBadge(
                        icon: Icons.schedule,
                        label: 'ETA',
                        value:
                            '${_formatEta(eta)}${booking.etaApproximate == true ? ' approx.' : ''}',
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Next driver action: $nextAction',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  _driverHint(booking),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _driverHint(BookingEntity booking) {
    if (booking.canDriverStartTrip) {
      return 'Begin the drive to ${booking.pickupDisplayName} and keep the pickup stop visible while you approach.';
    }
    if (booking.canDriverMarkArrived) {
      return 'Reach the pickup stop and confirm arrival once the rider can identify your vehicle.';
    }
    if (booking.canDriverMarkBoarded) {
      return 'The pickup stop is active. Confirm boarding only after the rider is seated and ready to depart.';
    }
    if (booking.canDriverMarkDroppedOff) {
      return 'Stay on the live route to ${booking.dropoffDisplayName} and confirm drop-off when the rider alights.';
    }
    if (booking.canParticipantCompleteJourney) {
      return 'Drop-off is recorded. Continue toward your destination or the next passenger stop.';
    }
    if (booking.isCompleted) {
      return 'This trip is complete. Open it if you need the final summary.';
    }
    return 'Open the trip workspace to review the latest operational context.';
  }

  String _driverTaskTitle(BookingEntity booking) {
    if (booking.canDriverStartTrip) {
      return 'Drive to pickup';
    }
    if (booking.canDriverMarkArrived) {
      return 'Arrive at pickup';
    }
    if (booking.canDriverMarkBoarded) {
      return 'Board rider';
    }
    if (booking.canDriverMarkDroppedOff) {
      return 'Drive to drop-off';
    }
    if (booking.canParticipantCompleteJourney) {
      return 'Drop-off complete';
    }
    if (booking.isCompleted) {
      return 'Trip complete';
    }
    return 'Active driving task';
  }

  String _driverTaskSubtitle(BookingEntity booking) {
    if (booking.canDriverStartTrip) {
      return 'You have an assigned rider and can start approaching the pickup stop now.';
    }
    if (booking.canDriverMarkArrived) {
      return 'Stay visible to the rider and confirm when you are at the meeting point.';
    }
    if (booking.canDriverMarkBoarded) {
      return 'Pickup is live. Complete boarding before leaving the stop.';
    }
    if (booking.canDriverMarkDroppedOff) {
      return 'The rider is onboard. Keep the route and ETA visible through drop-off.';
    }
    if (booking.canParticipantCompleteJourney) {
      return 'You can continue the route; this rider no longer needs a driver action.';
    }
    if (booking.isCompleted) {
      return 'This booking has no remaining driver actions.';
    }
    return 'Open the task to check the latest trip state.';
  }

  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${(seconds / 60).ceil()}m';
  }
}

class _JourneyBadge extends StatelessWidget {
  const _JourneyBadge({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
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
    final String ratingLabel =
        (rating == null || rating == 0) ? '—' : rating!.toStringAsFixed(1);

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

class _PostedRouteCard extends ConsumerWidget {
  const _PostedRouteCard({required this.route});

  final RouteEntity route;

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel route?'),
        content: const Text(
          'Passengers with existing bookings will be notified.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel route'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    await ref.read(cancelRouteProvider.notifier).cancel(route.routeId);
    final CancelRouteState result = ref.read(cancelRouteProvider);
    if (result.status == CancelRouteStatus.failed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not cancel route.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
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
                      Icon(Icons.schedule,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('EEE d MMM, HH:mm')
                            .format(route.departureDatetime.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.event_seat,
                          size: 14, color: scheme.onSurfaceVariant),
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
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  size: 20, color: scheme.onSurfaceVariant),
              onSelected: (String value) {
                if (value == 'view') {
                  unawaited(context.push('/routes/${route.routeId}'));
                } else if (value == 'cancel') {
                  unawaited(_confirmCancel(context, ref));
                }
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'view',
                  child: Text('View details'),
                ),
                PopupMenuItem<String>(
                  value: 'cancel',
                  child: Text('Cancel route'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
