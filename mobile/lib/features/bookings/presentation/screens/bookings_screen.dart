import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/async_views.dart';
import '../../domain/entities/booking_entity.dart';
import '../providers/booking_provider.dart';

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

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
                .where((BookingEntity b) => !_isCancelled(b) && !_isPast(b))
                .toList();

            return TabBarView(
              children: <Widget>[
                _BookingsTab(
                  bookings: upcoming,
                  icon: Icons.event_available,
                  emptyTitle: 'No upcoming bookings',
                  emptySubtitle: 'Search for routes to book your next ride',
                ),
                _BookingsTab(
                  bookings: past,
                  icon: Icons.history,
                  emptyTitle: 'No past bookings',
                ),
                _BookingsTab(
                  bookings: cancelled,
                  icon: Icons.cancel_outlined,
                  emptyTitle: 'No cancelled bookings',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BookingsTab extends ConsumerWidget {
  const _BookingsTab({
    required this.bookings,
    required this.icon,
    required this.emptyTitle,
    this.emptySubtitle,
  });

  final List<BookingEntity> bookings;
  final IconData icon;
  final String emptyTitle;
  final String? emptySubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookings.isEmpty) {
      return EmptyView(
        icon: icon,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(myBookingsProvider.future),
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
  return booking.status.contains('cancelled');
}

bool _isPast(BookingEntity booking) {
  return booking.status == 'completed' || booking.status == 'expired';
}
