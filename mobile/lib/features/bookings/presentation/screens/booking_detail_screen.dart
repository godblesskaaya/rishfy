import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../domain/entities/booking_entity.dart';
import '../providers/booking_provider.dart';

class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({required this.bookingId, super.key});

  final String bookingId;

  @override
  ConsumerState<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  bool _busy = false;

  Future<void> _cancelBooking() async {
    setState(() => _busy = true);
    try {
      await ref.read(bookingDataSourceProvider).cancelBooking(widget.bookingId);
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      ref.invalidate(myBookingsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel booking: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rateBooking() async {
    final TextEditingController commentCtrl = TextEditingController();
    int rating = 5;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setDialogState) {
            return AlertDialog(
              title: const Text('Rate this trip'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<int>(
                    value: rating,
                    decoration: const InputDecoration(labelText: 'Rating'),
                    items: List<DropdownMenuItem<int>>.generate(
                      5,
                      (int i) => DropdownMenuItem<int>(
                        value: i + 1,
                        child: Text('${i + 1} star${i == 0 ? '' : 's'}'),
                      ),
                    ),
                    onChanged: (int? value) {
                      if (value == null) return;
                      setDialogState(() => rating = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comment (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      commentCtrl.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(bookingDataSourceProvider).rateTrip(
            bookingId: widget.bookingId,
            rating: rating,
            comment: commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim(),
          );
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      ref.invalidate(myBookingsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit rating: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      commentCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BookingEntity> asyncBooking =
        ref.watch(bookingDetailProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: asyncBooking.when(
        loading: () => const LoadingView(message: 'Loading booking...'),
        error: (Object e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(bookingDetailProvider(widget.bookingId)),
        ),
        data: (BookingEntity booking) {
          final bool canCancel =
              booking.status == 'pending' || booking.status == 'confirmed';
          final bool canRate = booking.status == 'completed';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${booking.originName ?? 'Route'} → ${booking.destinationName ?? ''}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(label: 'Booking ID', value: booking.bookingId),
                        _DetailRow(
                          label: 'Created',
                          value: DateFormat('EEE, d MMM y · HH:mm')
                              .format(booking.createdAt.toLocal()),
                        ),
                        if (booking.departureDatetime != null)
                          _DetailRow(
                            label: 'Departure',
                            value: DateFormat('EEE, d MMM y · HH:mm')
                                .format(booking.departureDatetime!.toLocal()),
                          ),
                        _DetailRow(label: 'Status', value: booking.status),
                        _DetailRow(label: 'Payment', value: booking.paymentStatus),
                        _DetailRow(label: 'Seats', value: '${booking.seatCount}'),
                        _DetailRow(
                          label: 'Total',
                          value: 'TZS ${NumberFormat('#,###').format(booking.totalPriceTzs)}',
                        ),
                        if (booking.confirmationCode != null)
                          _DetailRow(
                            label: 'Confirmation code',
                            value: booking.confirmationCode!,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (canCancel)
                  PrimaryButton(
                    label: 'Cancel booking',
                    loading: _busy,
                    onPressed: _busy ? null : _cancelBooking,
                  ),
                if (canRate) ...<Widget>[
                  if (canCancel) const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Rate trip',
                    loading: _busy,
                    onPressed: _busy ? null : _rateBooking,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
