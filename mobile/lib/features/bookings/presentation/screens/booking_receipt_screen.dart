import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../data/models/payment_detail_models.dart';
import '../../domain/entities/booking_entity.dart';
import '../providers/booking_provider.dart';

class BookingReceiptScreen extends ConsumerWidget {
  const BookingReceiptScreen({required this.bookingId, super.key});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BookingEntity> bookingAsync =
        ref.watch(bookingDetailProvider(bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: bookingAsync.when(
        loading: () => const LoadingView(message: 'Loading receipt'),
        error: (Object error, _) => ErrorView.fromException(
          error,
          onRetry: () => ref.invalidate(bookingDetailProvider(bookingId)),
        ),
        data: (BookingEntity booking) {
          final AsyncValue<PaymentDetailDto>? paymentAsync =
              booking.paymentId == null
                  ? null
                  : ref.watch(paymentDetailProvider(booking.paymentId!));
          return RefreshIndicator(
            onRefresh: () async {
              await ref.refresh(bookingDetailProvider(bookingId).future);
              if (booking.paymentId != null) {
                await ref.refresh(
                  paymentDetailProvider(booking.paymentId!).future,
                );
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              children: <Widget>[
                _ReceiptHeader(booking: booking, paymentAsync: paymentAsync),
                const SizedBox(height: 20),
                _ReceiptSection(
                  title: 'Trip',
                  children: <Widget>[
                    _ReceiptRow(label: 'From', value: booking.pickupDisplayName),
                    _ReceiptRow(label: 'To', value: booking.dropoffDisplayName),
                    _ReceiptRow(
                      label: 'Seats',
                      value: '${booking.seatCount}',
                    ),
                    _ReceiptRow(
                      label: 'Booked',
                      value: DateFormat('dd MMM yyyy, HH:mm')
                          .format(booking.createdAt.toLocal()),
                    ),
                    if (booking.confirmationCode != null)
                      _ReceiptRow(
                        label: 'Confirmation',
                        value: booking.confirmationCode!,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _PaymentDetailSection(
                  booking: booking,
                  paymentAsync: paymentAsync,
                ),
                const SizedBox(height: 16),
                _PaymentStatusNotice(
                  booking: booking,
                  paymentAsync: paymentAsync,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReceiptHeader extends StatelessWidget {
  const _ReceiptHeader({
    required this.booking,
    required this.paymentAsync,
  });

  final BookingEntity booking;
  final AsyncValue<PaymentDetailDto>? paymentAsync;

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final PaymentDetailDto? payment = paymentAsync?.valueOrNull;
    final int displayAmount = payment?.netPaidTzs ?? booking.totalPriceTzs;
    final String heading =
        (payment?.refundedAmountTzs ?? 0) > 0 ? 'Net paid' : 'Total paid';
    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            heading,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            _tzs(displayAmount),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _ReceiptStatusChip(status: payment?.status ?? booking.paymentStatus),
        ],
      ),
    );
  }
}

class _PaymentDetailSection extends StatelessWidget {
  const _PaymentDetailSection({
    required this.booking,
    required this.paymentAsync,
  });

  final BookingEntity booking;
  final AsyncValue<PaymentDetailDto>? paymentAsync;

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PaymentDetailDto>? async = paymentAsync;
    if (async == null) {
      return _ReceiptSection(
        title: 'Payment',
        children: <Widget>[
          _ReceiptRow(label: 'Fare', value: _tzs(booking.totalPriceTzs)),
          _ReceiptRow(label: 'Status', value: booking.paymentStatus),
        ],
      );
    }

    return async.when(
      loading: () => _ReceiptSection(
        title: 'Payment',
        children: const <Widget>[
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Text('Loading payment detail...'),
        ],
      ),
      error: (_, __) => _ReceiptSection(
        title: 'Payment',
        children: <Widget>[
          _ReceiptRow(label: 'Fare', value: _tzs(booking.totalPriceTzs)),
          _ReceiptRow(label: 'Status', value: booking.paymentStatus),
          if (booking.paymentId != null)
            _ReceiptRow(label: 'Payment ID', value: booking.paymentId!),
          const Text('Detailed payment history is unavailable right now.'),
        ],
      ),
      data: (PaymentDetailDto payment) {
        return _ReceiptSection(
          title: 'Payment',
          children: <Widget>[
            _ReceiptRow(label: 'Fare', value: _tzs(payment.amountTzs)),
            if (payment.refundedAmountTzs > 0)
              _ReceiptRow(
                label: 'Refunded',
                value: _tzs(payment.refundedAmountTzs),
              ),
            if (payment.refundedAmountTzs > 0)
              _ReceiptRow(label: 'Net paid', value: _tzs(payment.netPaidTzs)),
            _ReceiptRow(label: 'Status', value: payment.status),
            _ReceiptRow(label: 'Method', value: payment.method),
            _ReceiptRow(label: 'Payment ID', value: payment.paymentId),
            if (payment.internalReference.isNotEmpty)
              _ReceiptRow(
                label: 'Internal ref',
                value: payment.internalReference,
              ),
            if (payment.providerReference != null)
              _ReceiptRow(
                label: 'Provider ref',
                value: payment.providerReference!,
              ),
            if (payment.failureMessage != null)
              _ReceiptRow(label: 'Failure', value: payment.failureMessage!),
            _ReceiptRow(
              label: 'Initiated',
              value: DateFormat('dd MMM yyyy, HH:mm')
                  .format(payment.initiatedAt.toLocal()),
            ),
            if (payment.completedAt != null)
              _ReceiptRow(
                label: 'Completed',
                value: DateFormat('dd MMM yyyy, HH:mm')
                    .format(payment.completedAt!.toLocal()),
              ),
            if (payment.failedAt != null)
              _ReceiptRow(
                label: 'Failed',
                value: DateFormat('dd MMM yyyy, HH:mm')
                    .format(payment.failedAt!.toLocal()),
              ),
            if (payment.hasRefunds) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Refunds',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              if (payment.refunds.isEmpty)
                Text(
                  'Refund amount is recorded, but refund event detail is not available.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ...payment.refunds.map(
                  (PaymentRefundDto refund) => _RefundTimelineItem(
                    refund: refund,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _RefundTimelineItem extends StatelessWidget {
  const _RefundTimelineItem({required this.refund});

  final PaymentRefundDto refund;

  String _tzs(int value) => 'TZS ${NumberFormat('#,###').format(value)}';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool failed = refund.status == 'failed';
    final Color color = failed ? scheme.error : scheme.primary;
    final DateTime timestamp =
        refund.completedAt ?? refund.failedAt ?? refund.requestedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                failed ? Icons.error_outline : Icons.undo,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_tzs(refund.amountTzs)} · ${refund.status.replaceAll('_', ' ')}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${refund.policy.replaceAll('_', ' ')} · ${refund.reason.replaceAll('_', ' ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('dd MMM yyyy, HH:mm').format(timestamp.toLocal()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (refund.providerReference != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Reference ${refund.providerReference}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (refund.failureReason != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              refund.failureReason!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptSection extends StatelessWidget {
  const _ReceiptSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentStatusNotice extends StatelessWidget {
  const _PaymentStatusNotice({
    required this.booking,
    required this.paymentAsync,
  });

  final BookingEntity booking;
  final AsyncValue<PaymentDetailDto>? paymentAsync;

  @override
  Widget build(BuildContext context) {
    final PaymentDetailDto? payment = paymentAsync?.valueOrNull;
    final String status = (payment?.status ?? booking.paymentStatus).toLowerCase();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String message;
    if ((payment?.refundedAmountTzs ?? 0) > 0 && status == 'partially_refunded') {
      message =
          'A partial refund is recorded. The net paid amount reflects the refund.';
    } else if ((payment?.refundedAmountTzs ?? 0) > 0 && status == 'refunded') {
      message =
          'This payment has been fully refunded. Keep the provider reference for support.';
    } else if (status == 'completed' || status == 'confirmed') {
      message =
          'Payment is complete. Keep this receipt for support reference.';
    } else if (status == 'failed') {
      message =
          'Payment failed. Open the booking to try the payment again or contact support.';
    } else if (status == 'refunded') {
      message = 'This payment has been refunded.';
    } else if (status == 'partially_refunded') {
      message = 'This payment has been partially refunded.';
    } else {
      message =
          'Payment is still being processed. Refresh this receipt for the latest status.';
    }
    final Color color = status == 'failed' ? scheme.error : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ReceiptStatusChip extends StatelessWidget {
  const _ReceiptStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String normalized = status.toLowerCase();
    final bool failed = normalized == 'failed';
    final bool complete = normalized == 'completed' || normalized == 'confirmed';
    final Color color = complete
        ? scheme.primary
        : failed
            ? scheme.error
            : scheme.tertiary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        label: Text(status.replaceAll('_', ' ')),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        labelStyle: TextStyle(color: color),
        backgroundColor: color.withValues(alpha: 0.08),
      ),
    );
  }
}
