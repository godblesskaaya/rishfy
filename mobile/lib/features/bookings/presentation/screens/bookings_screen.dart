import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/async_views.dart';

/// Tabs: Upcoming | Past | Cancelled.
/// Wire up in Sprint 3 with booking-service ListUserBookings.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        body: const TabBarView(
          children: <Widget>[
            EmptyView(
              icon: Icons.event_available,
              title: 'No upcoming bookings',
              subtitle: 'Search for routes to book your next ride',
            ),
            EmptyView(
              icon: Icons.history,
              title: 'No past bookings',
            ),
            EmptyView(
              icon: Icons.cancel_outlined,
              title: 'No cancelled bookings',
            ),
          ],
        ),
      ),
    );
  }
}
