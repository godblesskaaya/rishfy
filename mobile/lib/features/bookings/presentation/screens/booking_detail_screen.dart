import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/async_views.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../../domain/entities/booking_entity.dart';
import '../providers/booking_provider.dart';

class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({required this.bookingId, super.key});

  final String bookingId;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  bool _busy = false;
  Timer? _countdownTimer;
  Duration _declineTimeLeft = Duration.zero;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(DateTime createdAt) {
    _countdownTimer?.cancel();
    _updateCountdown(createdAt);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateCountdown(createdAt);
    });
  }

  void _updateCountdown(DateTime createdAt) {
    final DateTime expiresAt = createdAt.add(const Duration(minutes: 10));
    final Duration left = expiresAt.difference(DateTime.now());
    setState(() => _declineTimeLeft = left.isNegative ? Duration.zero : left);
    if (_declineTimeLeft == Duration.zero) {
      _countdownTimer?.cancel();
    }
  }

  Future<void> _cancelBooking() async {
    final String? reason = await _showCancelReasonDialog();
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(bookingDataSourceProvider)
          .cancelBooking(widget.bookingId, reason: reason);
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      ref.invalidate(myBookingsProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error, 'cancel booking'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showCancelReasonDialog() async {
    final TextEditingController controller = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Let the other rider know why (optional).'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep booking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    final String value = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return null;
    return value;
  }

  Future<void> _declineBooking() async {
    final String? reason = await _showDeclineReasonDialog();
    if (reason == null) return;

    final DeclineBookingState result = await ref
        .read(declineBookingProvider.notifier)
        .decline(widget.bookingId, reason: reason.isEmpty ? null : reason)
        .then((_) => ref.read(declineBookingProvider));

    if (!mounted) return;
    if (result.status == DeclineBookingStatus.success) {
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      ref.invalidate(myDriverBookingsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking declined.')),
      );
    } else if (result.status == DeclineBookingStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Failed to decline booking')),
      );
    }
  }

  Future<String?> _showDeclineReasonDialog() async {
    final TextEditingController controller = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Decline booking'),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _rateBooking() async {
    final TextEditingController commentCtrl = TextEditingController();
    int rating = 5;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(void Function()) setDialogState,
          ) {
            final String ratingLabel =
                '$rating star${rating == 1 ? '' : 's'}';
            return AlertDialog(
              title: const Text('Rate this trip'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    ratingLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(5, (int index) {
                      final int value = index + 1;
                      return IconButton(
                        tooltip: '$value star${value == 1 ? '' : 's'}',
                        onPressed: () {
                          setDialogState(() => rating = value);
                        },
                        icon: Icon(
                          value <= rating ? Icons.star : Icons.star_border,
                          color: Theme.of(context).colorScheme.primary,
                          size: 32,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Review (optional)',
                      hintText: 'Share what went well or what needs attention',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reviews may be moderated before appearing publicly.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
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
            comment: commentCtrl.text.trim().isEmpty
                ? null
                : commentCtrl.text.trim(),
          );
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      ref.invalidate(myBookingsProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error, 'submit rating'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      commentCtrl.dispose();
    }
  }

  Future<void> _saveFavoriteDriver(String driverId) async {
    setState(() => _busy = true);
    await ref.read(favoriteDriverActionProvider.notifier).add(driverId);
    final FavoriteDriverActionState result =
        ref.read(favoriteDriverActionProvider);
    if (!mounted) return;
    if (result.status == FavoriteDriverActionStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver saved to favorites.')),
      );
    } else if (result.status == FavoriteDriverActionStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not save driver.')),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _blockParticipant({
    required String userId,
    required String label,
  }) async {
    final TextEditingController reasonCtrl = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Block $label?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'You will not be intentionally matched with this $label again.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonCtrl.text.trim()),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null) return;

    setState(() => _busy = true);
    await ref
        .read(blockedUserActionProvider.notifier)
        .block(userId, reason: reason.isEmpty ? null : reason);
    final BlockedUserActionState result = ref.read(blockedUserActionProvider);
    if (!mounted) return;
    if (result.status == BlockedUserActionStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label blocked.')),
      );
    } else if (result.status == BlockedUserActionStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not block $label.')),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reportEmergency() async {
    final TextEditingController reasonCtrl = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Report safety issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'This sends a trip safety report to support and may trigger a payout review.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonCtrl.text.trim()),
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null) return;

    setState(() => _busy = true);
    await ref
        .read(emergencyReportProvider.notifier)
        .report(widget.bookingId, reason: reason.isEmpty ? null : reason);
    final EmergencyReportState result = ref.read(emergencyReportProvider);
    if (!mounted) return;
    if (result.status == EmergencyReportStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Safety report submitted.')),
      );
    } else if (result.status == EmergencyReportStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not submit report.')),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  String _friendlyError(Object error, String action) {
    if (error is AppException) return error.message;
    return 'Failed to $action. Please try again.';
  }

  String _formatCountdown(Duration duration) {
    final int mins = duration.inMinutes;
    final int secs = duration.inSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _leaveDetails(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/bookings');
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BookingEntity> asyncBooking =
        ref.watch(bookingDetailProvider(widget.bookingId));
    final String? currentUserId = ref.watch(currentUserProvider)?.userId;
    final DeclineBookingState declineState = ref.watch(declineBookingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _leaveDetails(context),
        ),
      ),
      body: asyncBooking.when(
        loading: () => const LoadingView(message: 'Loading booking...'),
        error: (Object error, _) => ErrorView(
          message: error.toString(),
          onRetry: () =>
              ref.invalidate(bookingDetailProvider(widget.bookingId)),
        ),
        data: (BookingEntity booking) {
          final bool isDriver =
              currentUserId != null && booking.driverId == currentUserId;
          final bool canCancel = !isDriver &&
              (booking.isPending ||
                  booking.effectiveJourneyState == 'confirmed');
          final bool canRate = booking.isCompleted;
          final bool declineWindowOpen =
              isDriver && booking.normalizedStatus == 'pending';
          final bool canDecline =
              declineWindowOpen && _declineTimeLeft > Duration.zero;
          final bool canOpenJourney = booking.isJourneyActive ||
              booking.effectiveJourneyState == 'confirmed';
          final bool canSaveDriver = !isDriver && booking.driverId != null;
          final String? blockTargetUserId =
              isDriver ? booking.passengerUserId : booking.driverId;
          final String blockTargetLabel = isDriver ? 'passenger' : 'driver';

          if (declineWindowOpen && _countdownTimer == null) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _startCountdown(booking.createdAt),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _BookingSummaryCard(booking: booking),
                const SizedBox(height: 16),
                _BookingStatusTimeline(status: booking.effectiveJourneyState),
                const SizedBox(height: 16),
                _PaymentSummaryCard(booking: booking),
                const SizedBox(height: 16),
                _BookingActionCard(
                  booking: booking,
                  isDriver: isDriver,
                ),
                const SizedBox(height: 16),
                if (declineWindowOpen) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spaceMd),
                    decoration: BoxDecoration(
                      color: _declineTimeLeft > Duration.zero
                          ? Theme.of(context).colorScheme.tertiaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.timer_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _declineTimeLeft > Duration.zero
                                ? 'Decline window: ${_formatCountdown(_declineTimeLeft)}'
                                : 'Decline window expired',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (canOpenJourney) ...<Widget>[
                  PrimaryButton(
                    label: booking.isJourneyActive
                        ? 'Open live trip'
                        : 'Open journey workspace',
                    icon: Icons.alt_route,
                    onPressed: () => context.push('/trip/${booking.bookingId}'),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/bookings/${booking.bookingId}/receipt'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View receipt'),
                ),
                const SizedBox(height: 12),
                if (canDecline) ...<Widget>[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onPressed:
                        declineState.status == DeclineBookingStatus.loading
                            ? null
                            : _declineBooking,
                    icon: const Icon(Icons.close),
                    label: const Text('Decline booking'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (canCancel) ...<Widget>[
                  PrimaryButton(
                    label: 'Cancel booking',
                    loading: _busy,
                    onPressed: _busy ? null : _cancelBooking,
                  ),
                  const SizedBox(height: 12),
                ],
                if (canSaveDriver) ...<Widget>[
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/drivers/${booking.driverId!}'),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('View driver profile'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _saveFavoriteDriver(booking.driverId!),
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('Save driver'),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _busy ? null : _reportEmergency,
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('Report safety issue'),
                ),
                const SizedBox(height: 12),
                if (blockTargetUserId != null) ...<Widget>[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _busy
                        ? null
                        : () => _blockParticipant(
                              userId: blockTargetUserId,
                              label: blockTargetLabel,
                            ),
                    icon: const Icon(Icons.block),
                    label: Text('Block $blockTargetLabel'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (canRate)
                  PrimaryButton(
                    label: 'Rate trip',
                    loading: _busy,
                    onPressed: _busy ? null : _rateBooking,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookingSummaryCard extends StatelessWidget {
  const _BookingSummaryCard({required this.booking});

  final BookingEntity booking;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _BookingPill(
                  label: booking.journeyLabel,
                  color: scheme.primary,
                ),
                _BookingPill(
                  label: booking.effectiveRouteStatus,
                  color: scheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${booking.originName ?? 'Route'} -> '
              '${booking.destinationName ?? ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _BookingInfoChip(
                  icon: Icons.access_time,
                  label: booking.departureDatetime != null
                      ? DateFormat('EEE, d MMM | HH:mm')
                          .format(booking.departureDatetime!.toLocal())
                      : DateFormat('EEE, d MMM | HH:mm')
                          .format(booking.createdAt.toLocal()),
                ),
                _BookingInfoChip(
                  icon: Icons.event_seat,
                  label:
                      '${booking.seatCount} seat${booking.seatCount == 1 ? '' : 's'}',
                ),
                _BookingInfoChip(
                  icon: Icons.payments_outlined,
                  label:
                      'TZS ${NumberFormat('#,###').format(booking.totalPriceTzs)}',
                ),
                _BookingInfoChip(
                  icon: Icons.verified_outlined,
                  label: booking.paymentStatus,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (booking.confirmationCode != null)
              _DetailRow(
                label: 'Confirmation code',
                value: booking.confirmationCode!,
              ),
            _DetailRow(label: 'Pickup', value: booking.pickupDisplayName),
            _DetailRow(label: 'Drop-off', value: booking.dropoffDisplayName),
            if (booking.etaToPickupSeconds != null)
              _DetailRow(
                label: 'ETA to pickup',
                value: _formatEta(booking.etaToPickupSeconds!),
              ),
            if (booking.etaToDropoffSeconds != null)
              _DetailRow(
                label: 'ETA to drop-off',
                value: _formatEta(booking.etaToDropoffSeconds!),
              ),
          ],
        ),
      ),
    );
  }

  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${(seconds / 60).ceil()}m';
  }
}

class _BookingActionCard extends StatelessWidget {
  const _BookingActionCard({
    required this.booking,
    required this.isDriver,
  });

  final BookingEntity booking;
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String title = booking.isJourneyActive
        ? 'Current trip focus'
        : booking.canParticipantCompleteJourney
            ? 'Final walk'
            : 'Current status';
    final String message =
        isDriver ? _driverMessage(booking) : _passengerMessage(booking);

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _driverMessage(BookingEntity booking) {
    if (booking.canDriverStartTrip) {
      return 'Start approaching the pickup point and keep the route workspace open.';
    }
    if (booking.canDriverMarkArrived) {
      return 'Reach the pickup stop and confirm arrival when the rider can identify you.';
    }
    if (booking.canDriverMarkBoarded) {
      return 'Board the rider and begin the in-vehicle leg.';
    }
    if (booking.canDriverMarkDroppedOff) {
      return 'Stay on the route and complete the drop-off when the rider alights.';
    }
    if (booking.canParticipantCompleteJourney) {
      return 'Your driving work is done. The rider is finishing the last walking segment.';
    }
    return 'Open the live trip if you need more operational detail.';
  }

  String _passengerMessage(BookingEntity booking) {
    if (booking.isPrePickupJourney) {
      return 'Head to pickup and keep your phone nearby for live driver updates.';
    }
    if (booking.isInVehicleJourney) {
      return 'Track the ride progress and ETA to your drop-off stop.';
    }
    if (booking.canParticipantCompleteJourney) {
      return 'Finish the final walk to your destination and close the journey when done.';
    }
    if (booking.isCompleted) {
      return 'This trip is complete. You can review the booking summary and rate it.';
    }
    return 'Check this booking for the latest trip details.';
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({required this.booking});

  final BookingEntity booking;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String status = booking.paymentStatus.toLowerCase();
    final bool failed = status == 'failed';
    final bool refunded =
        status == 'refunded' || status == 'partially_refunded';
    final bool complete = status == 'completed' || status == 'confirmed';
    final Color color = failed
        ? scheme.error
        : refunded
            ? scheme.tertiary
            : complete
                ? scheme.primary
                : scheme.secondary;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.payments_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                _BookingPill(
                  label: booking.paymentStatus.replaceAll('_', ' '),
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Amount',
              value:
                  'TZS ${NumberFormat('#,###').format(booking.totalPriceTzs)}',
            ),
            if (booking.paymentId != null)
              _DetailRow(label: 'Payment ID', value: booking.paymentId!),
            const SizedBox(height: 8),
            Text(
              _paymentMessage(status),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _paymentMessage(String status) {
    if (status == 'completed' || status == 'confirmed') {
      return 'Payment is posted for this booking.';
    }
    if (status == 'refunded') {
      return 'This booking payment has been refunded.';
    }
    if (status == 'partially_refunded') {
      return 'This booking payment has a partial refund recorded.';
    }
    if (status == 'failed') {
      return 'Payment failed. Check support or retry from the payment flow.';
    }
    return 'Payment is still being processed.';
  }
}

class _BookingPill extends StatelessWidget {
  const _BookingPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _BookingInfoChip extends StatelessWidget {
  const _BookingInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BookingStatusTimeline extends StatelessWidget {
  const _BookingStatusTimeline({required this.status});

  final String status;

  static const List<({String key, String label})> _steps =
      <({String key, String label})>[
    (key: 'pending', label: 'Pending'),
    (key: 'confirmed', label: 'Confirmed'),
    (key: 'driver_approaching', label: 'Approaching'),
    (key: 'driver_arrived', label: 'Arrived'),
    (key: 'in_transit', label: 'In transit'),
    (key: 'walking_to_destination', label: 'Final walk'),
    (key: 'completed', label: 'Completed'),
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isExceptionState =
        status == 'cancelled' || status == 'no_show' || status == 'declined';
    final int activeIndex = _timelineIndex(status);

    return Row(
      children: List<Widget>.generate(_steps.length * 2 - 1, (int index) {
        if (index.isOdd) {
          final int stepIndex = index ~/ 2;
          final bool passed = !isExceptionState && stepIndex < activeIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: passed ? scheme.primary : scheme.outlineVariant,
            ),
          );
        }

        final int stepIndex = index ~/ 2;
        final bool isActive = !isExceptionState && stepIndex == activeIndex;
        final bool passed = !isExceptionState && stepIndex < activeIndex;
        final bool isExceptionHere = isExceptionState &&
            stepIndex == activeIndex.clamp(0, _steps.length - 1);

        final Color circleColor = isExceptionHere
            ? scheme.error
            : (isActive || passed)
                ? scheme.primary
                : scheme.outlineVariant;
        final Color textColor = (isActive || passed || isExceptionHere)
            ? scheme.onSurface
            : scheme.onSurfaceVariant;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isActive || passed) && !isExceptionHere
                    ? circleColor
                    : Colors.transparent,
                border: Border.all(color: circleColor, width: 2),
              ),
              child: Center(
                child: isExceptionHere
                    ? Icon(Icons.close, size: 12, color: scheme.error)
                    : passed
                        ? Icon(Icons.check, size: 12, color: scheme.onPrimary)
                        : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _steps[stepIndex].label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: textColor,
                  ),
            ),
          ],
        );
      }),
    );
  }

  int _timelineIndex(String state) {
    switch (state) {
      case 'walking_to_pickup':
      case 'waiting_for_driver':
        return 1;
      case 'boarded':
      case 'approaching_dropoff':
        return 4;
      case 'dropped_off':
        return 5;
      case 'cancelled':
      case 'no_show':
        return 2;
      default:
        final int exact = _steps.indexWhere(
          (({String key, String label}) step) => step.key == state,
        );
        return exact >= 0 ? exact : 0;
    }
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
