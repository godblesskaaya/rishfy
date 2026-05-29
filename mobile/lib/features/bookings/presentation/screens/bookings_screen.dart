import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/providers/active_role_provider.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../domain/entities/booking_entity.dart';
import '../providers/booking_provider.dart';

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String activeRole = ref.watch(activeRoleProvider);
    return activeRole == 'driver'
        ? const _DriverBookingsView()
        : const _PassengerBookingsView();
  }
}

class _DriverBookingsView extends ConsumerWidget {
  const _DriverBookingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BookingEntity>> asyncBookings =
        ref.watch(myDriverBookingsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Driver operations'),
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: asyncBookings.when(
          loading: () =>
              const LoadingView(message: 'Loading your passengers...'),
          error: (Object error, _) => ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(myDriverBookingsProvider),
          ),
          data: (List<BookingEntity> bookings) {
            final List<BookingEntity> cancelled = bookings
                .where((BookingEntity booking) =>
                    booking.isCancelled || booking.isNoShow)
                .toList();
            final List<BookingEntity> past = bookings
                .where((BookingEntity booking) =>
                    !(booking.isCancelled || booking.isNoShow) &&
                    (booking.isCompleted ||
                        booking.isPostDropoffJourney ||
                        booking.status == 'expired'))
                .toList();
            final List<BookingEntity> upcoming = bookings
                .where((BookingEntity booking) =>
                    !(booking.isCancelled || booking.isNoShow) &&
                    !(booking.isCompleted ||
                        booking.isPostDropoffJourney ||
                        booking.status == 'expired'))
                .toList();

            return TabBarView(
              children: <Widget>[
                _BookingsTab(
                  bookings: upcoming,
                  role: _BookingRole.driver,
                  icon: Icons.directions_car_outlined,
                  emptyTitle: 'No upcoming driving tasks',
                  emptySubtitle:
                      'Post a route and active rider operations will appear here',
                  onRefresh: () => ref.refresh(myDriverBookingsProvider.future),
                ),
                _BookingsTab(
                  bookings: past,
                  role: _BookingRole.driver,
                  icon: Icons.history,
                  emptyTitle: 'No completed driving tasks yet',
                  onRefresh: () => ref.refresh(myDriverBookingsProvider.future),
                ),
                _BookingsTab(
                  bookings: cancelled,
                  role: _BookingRole.driver,
                  icon: Icons.cancel_outlined,
                  emptyTitle: 'No cancelled driving tasks',
                  onRefresh: () => ref.refresh(myDriverBookingsProvider.future),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PassengerBookingsView extends ConsumerWidget {
  const _PassengerBookingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BookingEntity>> asyncBookings =
        ref.watch(myBookingsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My bookings'),
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: asyncBookings.when(
          loading: () => const LoadingView(message: 'Loading your bookings...'),
          error: (Object error, _) => ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(myBookingsProvider),
          ),
          data: (List<BookingEntity> bookings) {
            final List<BookingEntity> cancelled = bookings
                .where((BookingEntity booking) =>
                    booking.isCancelled || booking.isNoShow)
                .toList();
            final List<BookingEntity> past = bookings
                .where((BookingEntity booking) =>
                    !(booking.isCancelled || booking.isNoShow) &&
                    (booking.isCompleted || booking.status == 'expired'))
                .toList();
            final List<BookingEntity> upcoming = bookings
                .where((BookingEntity booking) =>
                    !(booking.isCancelled || booking.isNoShow) &&
                    !(booking.isCompleted || booking.status == 'expired'))
                .toList();

            return TabBarView(
              children: <Widget>[
                _BookingsTab(
                  bookings: upcoming,
                  role: _BookingRole.passenger,
                  icon: Icons.event_available,
                  emptyTitle: 'No upcoming bookings',
                  emptySubtitle: 'Search for routes to book your next ride',
                  onRefresh: () => ref.refresh(myBookingsProvider.future),
                ),
                _BookingsTab(
                  bookings: past,
                  role: _BookingRole.passenger,
                  icon: Icons.history,
                  emptyTitle: 'No past bookings',
                  onRefresh: () => ref.refresh(myBookingsProvider.future),
                ),
                _BookingsTab(
                  bookings: cancelled,
                  role: _BookingRole.passenger,
                  icon: Icons.cancel_outlined,
                  emptyTitle: 'No cancelled bookings',
                  onRefresh: () => ref.refresh(myBookingsProvider.future),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _BookingRole { passenger, driver }

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({
    required this.bookings,
    required this.role,
    required this.icon,
    required this.emptyTitle,
    required this.onRefresh,
    this.emptySubtitle,
  });

  final List<BookingEntity> bookings;
  final _BookingRole role;
  final IconData icon;
  final String emptyTitle;
  final String? emptySubtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return EmptyView(
        icon: icon,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    final List<BookingEntity> sorted = <BookingEntity>[...bookings]
      ..sort((BookingEntity a, BookingEntity b) {
        final DateTime aTime = a.departureDatetime ?? a.createdAt;
        final DateTime bTime = b.departureDatetime ?? b.createdAt;
        final int aEta =
            a.etaToPickupSeconds ?? a.etaToDropoffSeconds ?? 1 << 20;
        final int bEta =
            b.etaToPickupSeconds ?? b.etaToDropoffSeconds ?? 1 << 20;
        if (a.isJourneyActive != b.isJourneyActive) {
          return a.isJourneyActive ? -1 : 1;
        }
        if (aEta != bEta) {
          return aEta.compareTo(bEta);
        }
        return aTime.compareTo(bTime);
      });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          return _BookingCard(
            booking: sorted[index],
            role: role,
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.role,
  });

  final BookingEntity booking;
  final _BookingRole role;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateTime departure = booking.departureDatetime ?? booking.createdAt;
    final String statusLabel = _statusLabel(booking);
    final Color statusColor = _statusColor(booking, scheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final String destination = booking.canOpenJourney
              ? '/trip/${booking.bookingId}'
              : '/bookings/${booking.bookingId}';
          unawaited(context.push(destination));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('d MMM | HH:mm').format(departure.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${booking.originName ?? '-'} -> ${booking.destinationName ?? '-'}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                _secondaryLine(booking),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Text(
                    'TZS ${NumberFormat('#,###').format(booking.totalPriceTzs)}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    role == _BookingRole.passenger &&
                            booking.canParticipantCompleteJourney
                        ? 'Finish journey'
                        : booking.canOpenJourney
                            ? booking.isJourneyActive
                                ? 'Open live trip'
                                : 'Open journey'
                            : 'View details',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _secondaryLine(BookingEntity booking) {
    final String seats =
        '${booking.seatCount} seat${booking.seatCount == 1 ? '' : 's'}';
    final String stopLabel = booking.nextStopLabel;
    final int? eta = booking.etaToPickupSeconds ?? booking.etaToDropoffSeconds;
    final List<String> parts = <String>[
      if (role == _BookingRole.driver) booking.passengerDisplayName,
      seats,
      stopLabel,
      if (eta != null) 'ETA ${_formatEta(eta)}',
    ];
    if (booking.canParticipantCompleteJourney &&
        booking.dropoffWalkingTime != null) {
      parts.add('Final walk ${(booking.dropoffWalkingTime! / 60).ceil()}m');
    }
    if (role == _BookingRole.driver) {
      if (booking.canParticipantCompleteJourney) {
        parts.add('Driver done');
      } else {
        parts.add('Next: ${booking.nextDriverActionLabel}');
      }
    } else if (role == _BookingRole.passenger &&
        booking.canParticipantCompleteJourney) {
      parts.add('Next: Finish final walk');
    }
    return parts.join(' | ');
  }

  String _statusLabel(BookingEntity booking) {
    if (booking.isCancelled) {
      if (booking.normalizedStatus == 'driver_cancelled') {
        return 'You cancelled';
      }
      if (booking.normalizedStatus == 'passenger_cancelled') {
        return role == _BookingRole.driver
            ? 'Passenger cancelled'
            : 'Cancelled';
      }
      return 'Cancelled';
    }
    if (booking.isNoShow) {
      return 'No show';
    }
    return booking.journeyLabel;
  }

  Color _statusColor(BookingEntity booking, ColorScheme scheme) {
    if (booking.isCancelled || booking.isNoShow) {
      return scheme.error;
    }
    if (booking.isCompleted) {
      return scheme.primary;
    }
    if (booking.isJourneyActive) {
      return Colors.blue.shade700;
    }
    if (booking.effectiveJourneyState == 'confirmed') {
      return Colors.green.shade700;
    }
    if (booking.isPending) {
      return Colors.orange.shade700;
    }
    return scheme.onSurfaceVariant;
  }

  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${(seconds / 60).ceil()}m';
  }
}
