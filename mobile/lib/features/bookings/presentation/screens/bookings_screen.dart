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
    final bool isDriverMode = activeRole == 'driver';

    if (isDriverMode) {
      return const _DriverBookingsView();
    }
    return const _PassengerBookingsView();
  }
}

// ── Driver view ────────────────────────────────────────────────────────────────

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
          title: const Text('Passenger trips'),
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
          error: (Object e, _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(myDriverBookingsProvider),
          ),
          data: (List<BookingEntity> bookings) {
            final List<BookingEntity> cancelled =
                bookings.where(_isCancelled).toList();
            final List<BookingEntity> past = bookings
                .where((BookingEntity b) => !_isCancelled(b) && _isPast(b))
                .toList();
            final List<BookingEntity> upcoming = bookings
                .where(
                    (BookingEntity b) => !_isCancelled(b) && !_isPast(b))
                .toList();

            return TabBarView(
              children: <Widget>[
                _DriverBookingsTab(
                  bookings: upcoming,
                  icon: Icons.directions_car_outlined,
                  emptyTitle: 'No upcoming passengers',
                  emptySubtitle:
                      'Post a route and passengers will book automatically',
                  onRefresh: () =>
                      ref.refresh(myDriverBookingsProvider.future),
                ),
                _DriverBookingsTab(
                  bookings: past,
                  icon: Icons.history,
                  emptyTitle: 'No completed trips yet',
                  onRefresh: () =>
                      ref.refresh(myDriverBookingsProvider.future),
                ),
                _DriverBookingsTab(
                  bookings: cancelled,
                  icon: Icons.cancel_outlined,
                  emptyTitle: 'No cancelled bookings',
                  onRefresh: () =>
                      ref.refresh(myDriverBookingsProvider.future),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DriverBookingsTab extends StatelessWidget {
  const _DriverBookingsTab({
    required this.bookings,
    required this.icon,
    required this.emptyTitle,
    required this.onRefresh,
    this.emptySubtitle,
  });

  final List<BookingEntity> bookings;
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
        final DateTime ta = a.departureDatetime ?? a.createdAt;
        final DateTime tb = b.departureDatetime ?? b.createdAt;
        return ta.compareTo(tb);
      });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          final BookingEntity booking = sorted[index];
          return _DriverBookingCard(booking: booking);
        },
      ),
    );
  }
}

class _DriverBookingCard extends StatelessWidget {
  const _DriverBookingCard({required this.booking});

  final BookingEntity booking;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String statusLabel = _driverStatusLabel(booking.status);
    final Color statusColor = _driverStatusColor(booking.status, scheme);
    final DateTime departure =
        booking.departureDatetime ?? booking.createdAt;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/bookings/${booking.bookingId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Status + time row
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
                    DateFormat('d MMM · HH:mm').format(departure.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Route
              Text(
                '${booking.originName ?? '—'} → ${booking.destinationName ?? '—'}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              // Seats + pickup
              Text(
                '${booking.seatCount} seat${booking.seatCount == 1 ? '' : 's'}'
                '${booking.suggestedPickupName != null ? ' · Pickup: ${booking.suggestedPickupName}' : ''}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              // Earnings + action arrow
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
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _driverStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Awaiting payment';
      case 'confirmed':
        return 'Ready to start';
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      case 'driver_cancelled':
        return 'You cancelled';
      case 'passenger_cancelled':
        return 'Passenger cancelled';
      case 'no_show':
        return 'No show';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color _driverStatusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'confirmed':
        return Colors.green.shade700;
      case 'pending':
        return Colors.orange.shade700;
      case 'completed':
        return scheme.primary;
      default:
        return scheme.onSurfaceVariant;
    }
  }
}

// ── Passenger view (unchanged) ─────────────────────────────────────────────────

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
          loading: () =>
              const LoadingView(message: 'Loading your bookings...'),
          error: (Object e, _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(myBookingsProvider),
          ),
          data: (List<BookingEntity> bookings) {
            final List<BookingEntity> cancelled =
                bookings.where(_isCancelled).toList();
            final List<BookingEntity> past = bookings
                .where((BookingEntity b) => !_isCancelled(b) && _isPast(b))
                .toList();
            final List<BookingEntity> upcoming = bookings
                .where(
                    (BookingEntity b) => !_isCancelled(b) && !_isPast(b))
                .toList();

            return TabBarView(
              children: <Widget>[
                _PassengerBookingsTab(
                  bookings: upcoming,
                  icon: Icons.event_available,
                  emptyTitle: 'No upcoming bookings',
                  emptySubtitle: 'Search for routes to book your next ride',
                  onRefresh: () => ref.refresh(myBookingsProvider.future),
                ),
                _PassengerBookingsTab(
                  bookings: past,
                  icon: Icons.history,
                  emptyTitle: 'No past bookings',
                  onRefresh: () => ref.refresh(myBookingsProvider.future),
                ),
                _PassengerBookingsTab(
                  bookings: cancelled,
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

class _PassengerBookingsTab extends StatelessWidget {
  const _PassengerBookingsTab({
    required this.bookings,
    required this.icon,
    required this.emptyTitle,
    required this.onRefresh,
    this.emptySubtitle,
  });

  final List<BookingEntity> bookings;
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

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          final BookingEntity booking = bookings[index];
          return Card(
            child: ListTile(
              onTap: () => context.push('/bookings/${booking.bookingId}'),
              title: Text(
                '${booking.originName ?? 'Route'} → ${booking.destinationName ?? ''}',
              ),
              subtitle: Text(
                '${DateFormat('EEE, d MMM · HH:mm').format((booking.departureDatetime ?? booking.createdAt).toLocal())}\nSeats: ${booking.seatCount}',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    'TZS ${NumberFormat('#,###').format(booking.totalPriceTzs)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    booking.status.replaceAll('_', ' '),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}

bool _isCancelled(BookingEntity booking) {
  return booking.status.contains('cancelled') ||
      booking.status == 'declined';
}

bool _isPast(BookingEntity booking) {
  return booking.status == 'completed' || booking.status == 'expired';
}
