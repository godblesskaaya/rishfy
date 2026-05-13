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
import '../../../trip/presentation/providers/trip_provider.dart';
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
    if (_declineTimeLeft == Duration.zero) _countdownTimer?.cancel();
  }

  Future<void> _startTrip(BookingEntity booking) async {
    setState(() => _busy = true);
    try {
      await ref.read(startTripProvider.notifier).start(booking.bookingId);
      if (!mounted) return;
      final TripActionState s = ref.read(startTripProvider);
      if (s.status == TripActionStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.error ?? 'Could not start trip')),
        );
        return;
      }
      await ref
          .read(driverBroadcastProvider.notifier)
          .startStreaming(booking.bookingId);
      if (!mounted) return;
      final DriverBroadcastState bs = ref.read(driverBroadcastProvider);
      if (bs.isStreaming) {
        context.push('/trip/${booking.bookingId}');
      } else if (bs.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not broadcast location: ${bs.error}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeTrip(BookingEntity booking) async {
    setState(() => _busy = true);
    try {
      await ref.read(completeTripProvider.notifier).complete(booking.bookingId);
      if (!mounted) return;
      final TripActionState s = ref.read(completeTripProvider);
      if (s.status == TripActionStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.error ?? 'Could not complete trip')),
        );
        return;
      }
      await ref.read(driverBroadcastProvider.notifier).stopStreaming();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip completed!')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e, 'cancel booking'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showCancelReasonDialog() async {
    final TextEditingController ctrl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Let the driver know why (optional).'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
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
    final String value = ctrl.text;
    ctrl.dispose();
    if (confirmed != true) return null;
    return value;
  }

  String _friendlyError(Object e, String action) {
    if (e is AppException) return e.message;
    return 'Failed to $action. Please try again.';
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
      ref.invalidate(myBookingsProvider);
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
    final TextEditingController ctrl = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Decline booking'),
        content: TextField(
          controller: ctrl,
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
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return reason;
  }

  Future<void> _rateBooking() async {
    final TextEditingController commentCtrl = TextEditingController();
    int rating = 5;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (BuildContext context, void Function(void Function()) setDialogState) {
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
            comment: commentCtrl.text.trim().isEmpty
                ? null
                : commentCtrl.text.trim(),
          );
      ref.invalidate(bookingDetailProvider(widget.bookingId));
      ref.invalidate(myBookingsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e, 'submit rating'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      commentCtrl.dispose();
    }
  }

  String _formatCountdown(Duration d) {
    final int mins = d.inMinutes;
    final int secs = d.inSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BookingEntity> asyncBooking =
        ref.watch(bookingDetailProvider(widget.bookingId));
    final String? currentUserId = ref.watch(currentUserProvider)?.userId;
    final DeclineBookingState declineState = ref.watch(declineBookingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Booking details')),
      body: asyncBooking.when(
        loading: () => const LoadingView(message: 'Loading booking...'),
        error: (Object e, _) => ErrorView(
          message: e.toString(),
          onRetry: () =>
              ref.invalidate(bookingDetailProvider(widget.bookingId)),
        ),
        data: (BookingEntity booking) {
          final bool canCancel =
              booking.status == 'pending' || booking.status == 'confirmed';
          final bool canRate = booking.status == 'completed';
          final bool isDriver = currentUserId != null &&
              booking.driverId == currentUserId;
          final bool canDecline = isDriver &&
              booking.status == 'pending' &&
              _declineTimeLeft > Duration.zero;
          final bool declineWindowOpen = isDriver && booking.status == 'pending';
          final bool isTrackable = booking.status == 'confirmed' ||
              booking.status == 'in_progress';
          final bool canStartTrip = isDriver && booking.status == 'confirmed';
          final bool canCompleteTrip =
              isDriver && booking.status == 'in_progress';
          final DriverBroadcastState broadcastState =
              ref.watch(driverBroadcastProvider);
          final TripActionState startState = ref.watch(startTripProvider);
          final TripActionState completeState =
              ref.watch(completeTripProvider);

          // Start countdown when booking data is first available
          if (declineWindowOpen && _countdownTimer == null) {
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _startCountdown(booking.createdAt));
          }

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
                          '${booking.originName ?? 'Route'} → '
                          '${booking.destinationName ?? ''}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                            label: 'Booking ID', value: booking.bookingId),
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
                        _DetailRow(
                            label: 'Payment', value: booking.paymentStatus),
                        _DetailRow(
                            label: 'Seats', value: '${booking.seatCount}'),
                        _DetailRow(
                          label: 'Total',
                          value:
                              'TZS ${NumberFormat('#,###').format(booking.totalPriceTzs)}',
                        ),
                        if (booking.confirmationCode != null)
                          _DetailRow(
                            label: 'Confirmation code',
                            value: booking.confirmationCode!,
                          ),
                        if (booking.suggestedPickupName != null)
                          _DetailRow(
                            label: 'Pickup point',
                            value: booking.suggestedPickupName!,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _BookingStatusTimeline(status: booking.status),
                const SizedBox(height: 16),
                // ── Decline section (drivers only) ─────────────────────
                if (declineWindowOpen) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spaceMd),
                    decoration: BoxDecoration(
                      color: _declineTimeLeft > Duration.zero
                          ? Theme.of(context).colorScheme.tertiaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  if (canDecline)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.error,
                        side: BorderSide(
                            color: Theme.of(context).colorScheme.error),
                      ),
                      onPressed: declineState.status ==
                              DeclineBookingStatus.loading
                          ? null
                          : _declineBooking,
                      icon: const Icon(Icons.close),
                      label: const Text('Decline booking'),
                    ),
                  const SizedBox(height: 8),
                ],
                // ── Live tracking entry (passenger or driver) ──────────
                if (isTrackable) ...<Widget>[
                  PrimaryButton(
                    label: isDriver ? 'Open trip map' : 'Track driver',
                    icon: Icons.location_on,
                    onPressed: () =>
                        context.push('/trip/${booking.bookingId}'),
                  ),
                  const SizedBox(height: 12),
                ],
                // ── Driver: start trip (begins location broadcast) ─────
                if (canStartTrip) ...<Widget>[
                  PrimaryButton(
                    label: (broadcastState.isStreaming ||
                            startState.status == TripActionStatus.loading)
                        ? 'Starting…'
                        : 'Start trip',
                    icon: Icons.play_arrow,
                    loading: startState.status == TripActionStatus.loading,
                    onPressed: (_busy ||
                            broadcastState.isStreaming ||
                            startState.status == TripActionStatus.loading)
                        ? null
                        : () => _startTrip(booking),
                  ),
                  if (broadcastState.error != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      broadcastState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                // ── Driver: complete trip ───────────────────────────────
                if (canCompleteTrip) ...<Widget>[
                  PrimaryButton(
                    label: completeState.status == TripActionStatus.loading
                        ? 'Completing…'
                        : 'Complete trip',
                    icon: Icons.check_circle_outline,
                    loading:
                        completeState.status == TripActionStatus.loading,
                    onPressed: (_busy ||
                            completeState.status == TripActionStatus.loading)
                        ? null
                        : () => _completeTrip(booking),
                  ),
                  if (completeState.error != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      completeState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                // ── Passenger actions ──────────────────────────────────
                if (canCancel && !isDriver)
                  PrimaryButton(
                    label: 'Cancel booking',
                    loading: _busy,
                    onPressed: _busy ? null : _cancelBooking,
                  ),
                if (canRate) ...<Widget>[
                  if (canCancel && !isDriver) const SizedBox(height: 12),
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

class _BookingStatusTimeline extends StatelessWidget {
  const _BookingStatusTimeline({required this.status});

  final String status;

  static const List<({String key, String label})> _steps = <({String key, String label})>[
    (key: 'pending', label: 'Pending'),
    (key: 'confirmed', label: 'Confirmed'),
    (key: 'in_progress', label: 'In Transit'),
    (key: 'completed', label: 'Completed'),
  ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isCancelled = status == 'cancelled' || status == 'declined';
    final int activeIndex =
        _steps.indexWhere((s) => s.key == status);

    return Row(
      children: List<Widget>.generate(_steps.length * 2 - 1, (int i) {
        if (i.isOdd) {
          final int stepIndex = i ~/ 2;
          final bool passed = !isCancelled && stepIndex < activeIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: passed ? scheme.primary : scheme.outlineVariant,
            ),
          );
        }
        final int stepIndex = i ~/ 2;
        final bool isActive = !isCancelled && stepIndex == activeIndex;
        final bool passed = !isCancelled && stepIndex < activeIndex;
        final bool isCancelledHere =
            isCancelled && stepIndex == activeIndex.clamp(0, _steps.length - 1);

        final Color circleColor = isCancelledHere
            ? scheme.error
            : (isActive || passed)
                ? scheme.primary
                : scheme.outlineVariant;
        final Color textColor = (isActive || passed || isCancelledHere)
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
                color: (isActive || passed) && !isCancelledHere
                    ? circleColor
                    : Colors.transparent,
                border: Border.all(color: circleColor, width: 2),
              ),
              child: Center(
                child: isCancelledHere
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
