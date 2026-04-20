import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';

/// Booking details + actions (cancel, rate, view trip).
/// Wire up in Sprint 3.
class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({required this.bookingId, super.key});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Center(child: Text('Booking: $bookingId')),
      ),
    );
  }
}
