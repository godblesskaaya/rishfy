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

class PassengerHomeScreen extends ConsumerWidget {
  const PassengerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? firstName = ref.watch(currentUserProvider)?.firstName;
    final bool canSwitch = ref.watch(canSwitchRolesProvider);
    final AsyncValue<List<BookingEntity>> bookingsAsync =
        ref.watch(myBookingsProvider);
    final AsyncValue<BookingEntity?> activeJourneyAsync =
        ref.watch(activePassengerJourneyProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Habari, ${firstName ?? ''}',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Where are you going today?',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
              if (canSwitch)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _RoleButton(
                          label: 'Passenger',
                          selected: true,
                          onTap: () {},
                        ),
                      ),
                      Expanded(
                        child: _RoleButton(
                          label: 'Driver',
                          selected: false,
                          onTap: () {
                            unawaited(
                              ref
                                  .read(activeRoleProvider.notifier)
                                  .setRole('driver'),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                onTap: () => context.go('/search'),
                child: Container(
                  padding: const EdgeInsets.all(AppConstants.spaceMd),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Where to?',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Current trip',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _PassengerJourneyCard(activeJourneyAsync: activeJourneyAsync),
              const SizedBox(height: 32),
              Text(
                'Quick actions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.history,
                      label: 'Recent\nroutes',
                      onTap: () => context.go('/bookings'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.favorite_border,
                      label: 'Saved\nplaces',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.emergency_outlined,
                      label: 'Emergency\ncontacts',
                      onTap: () {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Upcoming trips',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _UpcomingTripsCard(bookingsAsync: bookingsAsync),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassengerJourneyCard extends StatelessWidget {
  const _PassengerJourneyCard({required this.activeJourneyAsync});

  final AsyncValue<BookingEntity?> activeJourneyAsync;

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
        title: 'Checking your active trip',
        subtitle: 'We are loading the latest journey state.',
      ),
      error: (Object error, _) => placeholder(
        icon: Icons.error_outline,
        title: 'Could not load trip state',
        subtitle: error.toString(),
      ),
      data: (BookingEntity? booking) {
        if (booking == null) {
          return placeholder(
            icon: Icons.map_outlined,
            title: 'No active trip right now',
            subtitle: 'Your next confirmed booking will appear here.',
          );
        }

        final int? etaSeconds =
            booking.etaToPickupSeconds ?? booking.etaToDropoffSeconds;
        final String destination = booking.canOpenJourney
            ? '/trip/${booking.bookingId}'
            : '/bookings/${booking.bookingId}';
        final String actionLabel = booking.canParticipantCompleteJourney
            ? 'Finish final walk'
            : booking.canOpenJourney
                ? booking.isJourneyActive
                    ? 'Open live trip'
                    : 'Open journey workspace'
                : 'View booking';
        final String phaseHint = _phaseHint(booking);

        return InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          onTap: () => unawaited(context.push(destination)),
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              gradient: LinearGradient(
                colors: <Color>[
                  scheme.primaryContainer,
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
                        booking.journeyLabel,
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
                const SizedBox(height: 6),
                Text(
                  booking.isPrePickupJourney
                      ? 'Pickup: ${booking.pickupDisplayName}'
                      : 'Drop-off: ${booking.dropoffDisplayName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  phaseHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (booking.isPrePickupJourney &&
                    (booking.pickupWalkingDistance != null ||
                        booking.pickupWalkingTime != null)) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Walk to pickup ${_walkLabel(booking.pickupWalkingDistance, booking.pickupWalkingTime)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
                if (booking.isPostDropoffJourney &&
                    (booking.dropoffWalkingDistance != null ||
                        booking.dropoffWalkingTime != null) &&
                    !booking.isCompleted) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Final walk ${_walkLabel(booking.dropoffWalkingDistance, booking.dropoffWalkingTime)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
                if (etaSeconds != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'ETA ${_formatEta(etaSeconds)}'
                    '${booking.etaApproximate == true ? ' approx.' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  actionLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${(seconds / 60).ceil()}m';
  }

  String _phaseHint(BookingEntity booking) {
    switch (booking.effectiveJourneyState) {
      case 'confirmed':
      case 'walking_to_pickup':
        return 'Head to the pickup point before your driver arrives.';
      case 'waiting_for_driver':
        return 'You are at pickup. Keep your phone nearby for live updates.';
      case 'driver_approaching':
        return 'Your driver is close. Be ready to board at pickup.';
      case 'driver_arrived':
        return 'Your driver is waiting at pickup now.';
      case 'boarded':
      case 'in_transit':
      case 'approaching_dropoff':
        return 'You are onboard. Follow the route to your drop-off stop.';
      case 'dropped_off':
      case 'walking_to_destination':
        return 'You are on the final walking leg to your destination.';
      case 'completed':
        return 'This journey is complete.';
      default:
        return 'Open this journey for the latest trip context.';
    }
  }

  String _walkLabel(int? distanceMeters, int? timeSeconds) {
    final List<String> parts = <String>[];
    if (distanceMeters != null) {
      parts.add('${distanceMeters}m');
    }
    if (timeSeconds != null) {
      parts.add('${(timeSeconds / 60).ceil()} min');
    }
    return parts.isEmpty ? 'details pending' : parts.join(' | ');
  }
}

class _UpcomingTripsCard extends StatelessWidget {
  const _UpcomingTripsCard({required this.bookingsAsync});

  final AsyncValue<List<BookingEntity>> bookingsAsync;

  bool _isUpcoming(BookingEntity booking) {
    if (booking.isCancelled || booking.isNoShow) return false;
    if (booking.isCompleted || booking.status == 'expired') return false;
    return true;
  }

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
              Icon(Icons.event_available,
                  size: 48, color: scheme.onSurfaceVariant),
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

    return bookingsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, __) => emptyBox(
        'Could not load your trips',
        _messageFromError(error),
      ),
      data: (List<BookingEntity> bookings) {
        final List<BookingEntity> upcoming = bookings
            .where(_isUpcoming)
            .toList()
          ..sort((BookingEntity a, BookingEntity b) =>
              (a.departureDatetime ?? a.createdAt)
                  .compareTo(b.departureDatetime ?? b.createdAt));
        if (upcoming.isEmpty) {
          return emptyBox(
            'No upcoming trips',
            'Search for routes to book your next ride.',
          );
        }
        return Column(
          children: upcoming
              .take(2)
              .map((BookingEntity booking) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _UpcomingTripTile(booking: booking),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _UpcomingTripTile extends StatelessWidget {
  const _UpcomingTripTile({required this.booking});

  final BookingEntity booking;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateTime when = booking.departureDatetime ?? booking.createdAt;

    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      onTap: () {
        final String destination = booking.canOpenJourney
            ? '/trip/${booking.bookingId}'
            : '/bookings/${booking.bookingId}';
        unawaited(context.push(destination));
      },
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.event, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${booking.originName ?? 'Route'} -> '
                    '${booking.destinationName ?? ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('EEE d MMM, HH:mm').format(when.toLocal())}'
                    ' | ${booking.journeyLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    booking.canOpenJourney
                        ? 'Open journey workspace'
                        : 'View booking details',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
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

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
