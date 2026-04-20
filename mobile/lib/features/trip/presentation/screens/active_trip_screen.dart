import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';

/// Active trip view with live map tracking.
/// Wire up in Sprint 4 with:
///   - Google Maps widget showing route + driver position
///   - WebSocket connection to location-service for live updates
///   - Emergency contact button (LATRA-OR-08)
class ActiveTripScreen extends ConsumerWidget {
  const ActiveTripScreen({required this.bookingId, super.key});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your trip'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            onPressed: () {
              // TODO(Fatma): Trigger emergency notification flow
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Center(
          child: Text(
            'Live trip tracking\n\n'
            'Booking: $bookingId\n'
            'Connects to: ws://.../ws/location\n'
            'Shows: driver position, ETA, trip progress',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
