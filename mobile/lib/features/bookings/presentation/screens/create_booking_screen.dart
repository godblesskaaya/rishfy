import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/domain/payment_method.dart';
import '../../../profile/presentation/providers/payment_methods_provider.dart';
import '../../../routes/domain/entities/route_entity.dart';
import '../../../routes/presentation/providers/route_provider.dart';
import '../../data/models/booking_models.dart';
import '../providers/booking_provider.dart';

class CreateBookingScreen extends ConsumerStatefulWidget {
  const CreateBookingScreen({
    required this.routeId,
    super.key,
    this.driverId,
    this.pricePerSeat,
    this.suggestedPickupName,
    this.suggestedPickupLat,
    this.suggestedPickupLng,
    this.estimatedPickupTime,
    this.walkingDistanceToPickup,
    this.walkingTimeToPickup,
    this.walkingDistanceFromDropoff,
  });

  final String routeId;
  final String? driverId;
  final int? pricePerSeat;
  final String? suggestedPickupName;
  final double? suggestedPickupLat;
  final double? suggestedPickupLng;
  final DateTime? estimatedPickupTime;
  final int? walkingDistanceToPickup;
  final int? walkingTimeToPickup;
  final int? walkingDistanceFromDropoff;

  @override
  ConsumerState<CreateBookingScreen> createState() =>
      _CreateBookingScreenState();
}

class _CreateBookingScreenState extends ConsumerState<CreateBookingScreen> {
  String _paymentMethod = 'mpesa_tz';
  String _payerPhone = '';
  String _payerCountryCode = '+255';
  String _payerInitial = '';
  int _seatCount = 1;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Seed phone field from current user once.
    final String? userPhone =
        ref.read(currentUserProvider)?.phoneNumber;
    if (userPhone != null && userPhone.isNotEmpty) {
      // The user entity stores +255712345678 style. Strip the country code so
      // IntlPhoneField can render the local number.
      final RegExp tzPrefix = RegExp(r'^\+255');
      _payerInitial = userPhone.replaceFirst(tzPrefix, '');
      _payerPhone = _payerInitial;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await ref.read(createBookingProvider.notifier).pollPaymentStatus();
      final CreateBookingState s = ref.read(createBookingProvider);
      if (s.status == CreateBookingStatus.completed ||
          s.status == CreateBookingStatus.failed) {
        _pollTimer?.cancel();
      }
    });
  }

  String _strip(String full) {
    if (full.startsWith('+255')) return full.substring(4);
    if (full.startsWith('+')) {
      // Strip "+CC" where CC is 1-3 digits
      final RegExpMatch? m = RegExp(r'^\+\d{1,3}').firstMatch(full);
      if (m != null) return full.substring(m.end);
    }
    return full;
  }

  Future<void> _submit(RouteEntity route) async {
    final String number = _payerPhone.trim();
    if (number.isEmpty || number.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid mobile money number')),
      );
      return;
    }
    final String phone = '$_payerCountryCode$number';
    await ref.read(createBookingProvider.notifier).submit(
          CreateBookingRequest(
            routeId: widget.routeId,
            driverId: widget.driverId ?? route.driverUserId,
            seatsBooked: _seatCount,
            pricePerSeat: widget.pricePerSeat ?? route.pricePerSeatTzs,
            paymentMethod: _paymentMethod,
            payerPhone: phone,
            idempotencyKey: const Uuid().v4(),
            pickupName: route.originName,
            dropoffName: route.destinationName,
            pickupLat: route.originLat,
            pickupLng: route.originLng,
            dropoffLat: route.destinationLat,
            dropoffLng: route.destinationLng,
            suggestedPickupName: widget.suggestedPickupName,
            pickupPointLat: widget.suggestedPickupLat,
            pickupPointLng: widget.suggestedPickupLng,
            estimatedPickupTime: widget.estimatedPickupTime,
            pickupWalkingDistance: widget.walkingDistanceToPickup,
            pickupWalkingTime: widget.walkingTimeToPickup,
            dropoffWalkingDistance: widget.walkingDistanceFromDropoff,
          ),
        );
    final CreateBookingState s = ref.read(createBookingProvider);
    if (s.status == CreateBookingStatus.awaitingPayment && mounted) {
      _startPolling();
      await _showPaymentOverlay(
        context,
        ussdCode: s.paymentResponse?.ussdCode,
        providerLabel: _providerLabel(_paymentMethod),
        totalTzs: route.pricePerSeatTzs * _seatCount,
      );
    }
  }

  String _providerLabel(String method) {
    switch (method) {
      case 'mpesa_tz': return 'M-Pesa';
      case 'tigopesa': return 'TigoPesa';
      case 'airtel_money': return 'Airtel Money';
      case 'halopesa': return 'HaloPesa';
      default: return method;
    }
  }

  Future<void> _showPaymentOverlay(
    BuildContext ctx, {
    required String? ussdCode,
    required String providerLabel,
    required int totalTzs,
  }) async {
    await showModalBottomSheet<void>(
      context: ctx,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
      ),
      builder: (_) => _PaymentAwaitSheet(
        providerLabel: providerLabel,
        ussdCode: ussdCode,
        totalTzs: totalTzs,
        onDone: () {
          _pollTimer?.cancel();
          final CreateBookingState s = ref.read(createBookingProvider);
          Navigator.of(ctx).pop();
          if (s.status == CreateBookingStatus.completed &&
              s.paymentResponse != null) {
            context.go('/bookings/${s.paymentResponse!.bookingId}');
          } else if (s.status == CreateBookingStatus.failed) {
            // Reset so the next submit goes through cleanly.
            ref.read(createBookingProvider.notifier).reset();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<RouteEntity> asyncRoute =
        ref.watch(routeDetailProvider(widget.routeId));
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm booking')),
      body: asyncRoute.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Failed to load: $e')),
        data: (RouteEntity route) => _buildForm(context, route),
      ),
    );
  }

  Widget _buildForm(BuildContext context, RouteEntity route) {
    final CreateBookingState bookingState = ref.watch(createBookingProvider);
    final bool isLoading = bookingState.status == CreateBookingStatus.loading;
    final String totalPrice =
        'TZS ${NumberFormat('#,###').format(route.pricePerSeatTzs * _seatCount)}';
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
                  Text('${route.originName} → ${route.destinationName}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('TZS ${NumberFormat('#,###').format(route.pricePerSeatTzs)} / seat'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Seats', style: Theme.of(context).textTheme.titleSmall),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: _seatCount > 1 ? () => setState(() => _seatCount--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_seatCount', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                onPressed: _seatCount < route.availableSeats
                    ? () => setState(() => _seatCount++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              const Spacer(),
              Text(totalPrice,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 20),
          Text('Mobile money number', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          IntlPhoneField(
            // Key forces rebuild when a saved method is tapped so initialValue takes effect.
            key: ValueKey<String>('phone_$_payerInitial'),
            initialCountryCode: 'TZ',
            initialValue: _payerInitial,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '712 345 678',
              border: OutlineInputBorder(),
            ),
            onChanged: (PhoneNumber phone) {
              setState(() {
                _payerPhone = phone.number;
                _payerCountryCode = phone.countryCode;
              });
            },
          ),
          const SizedBox(height: 20),
          Text('Payment method', style: Theme.of(context).textTheme.titleSmall),
          Consumer(builder: (BuildContext ctx, WidgetRef ref, _) {
            final List<PaymentMethod> saved =
                ref.watch(paymentMethodsProvider);
            if (saved.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 8,
                children: saved.map((PaymentMethod m) {
                  final bool selected =
                      m.provider == _paymentMethod && _payerPhone == _strip(m.phone);
                  return ChoiceChip(
                    avatar: const Icon(Icons.account_balance_wallet, size: 16),
                    label: Text(
                      m.label.isEmpty
                          ? '${m.providerDisplayName} · ${m.phone}'
                          : '${m.label} · ${m.providerDisplayName}',
                    ),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _paymentMethod = m.provider;
                        _payerInitial = _strip(m.phone);
                        _payerPhone = _payerInitial;
                        if (m.phone.startsWith('+255')) {
                          _payerCountryCode = '+255';
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            );
          }),
          RadioListTile<String>(
            title: const Text('M-Pesa'),
            value: 'mpesa_tz',
            groupValue: _paymentMethod,
            onChanged: (String? v) => setState(() => _paymentMethod = v!),
          ),
          RadioListTile<String>(
            title: const Text('TigoPesa'),
            value: 'tigopesa',
            groupValue: _paymentMethod,
            onChanged: (String? v) => setState(() => _paymentMethod = v!),
          ),
          RadioListTile<String>(
            title: const Text('Airtel Money'),
            value: 'airtel_money',
            groupValue: _paymentMethod,
            onChanged: (String? v) => setState(() => _paymentMethod = v!),
          ),
          RadioListTile<String>(
            title: const Text('HaloPesa'),
            value: 'halopesa',
            groupValue: _paymentMethod,
            onChanged: (String? v) => setState(() => _paymentMethod = v!),
          ),
          const SizedBox(height: 24),
          if (bookingState.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(bookingState.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          PrimaryButton(
            label: 'Pay $totalPrice',
            loading: isLoading,
            onPressed: isLoading ? null : () => _submit(route),
          ),
        ],
      ),
    );
  }
}

class _PaymentAwaitSheet extends ConsumerStatefulWidget {
  const _PaymentAwaitSheet({
    required this.providerLabel,
    required this.totalTzs,
    required this.onDone,
    this.ussdCode,
  });
  final String providerLabel;
  final String? ussdCode;
  final int totalTzs;
  final VoidCallback onDone;

  @override
  ConsumerState<_PaymentAwaitSheet> createState() => _PaymentAwaitSheetState();
}

class _PaymentAwaitSheetState extends ConsumerState<_PaymentAwaitSheet> {
  @override
  Widget build(BuildContext context) {
    final CreateBookingState s = ref.watch(createBookingProvider);
    final bool done = s.status == CreateBookingStatus.completed;
    final bool failed = s.status == CreateBookingStatus.failed;
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (done) ...<Widget>[
            const Icon(Icons.check_circle, color: Colors.green, size: 56),
            const SizedBox(height: 12),
            Text('Payment confirmed!', style: Theme.of(context).textTheme.titleLarge),
          ] else if (failed) ...<Widget>[
            const Icon(Icons.error_outline, color: Colors.red, size: 56),
            const SizedBox(height: 12),
            Text('Payment failed', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(s.error ?? 'Please try again.'),
          ] else ...<Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Waiting for ${widget.providerLabel} payment',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'TZS ${NumberFormat('#,###').format(widget.totalTzs)}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (widget.ussdCode != null) ...<Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Column(children: <Widget>[
                  const Text('Or dial USSD manually'),
                  const SizedBox(height: 4),
                  Text(widget.ussdCode!,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Check your phone for the ${widget.providerLabel} prompt.\nDo not close this screen.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          if (done || failed)
            PrimaryButton(
              label: done ? 'View booking' : 'Try again',
              onPressed: widget.onDone,
            )
          else
            TextButton(
              onPressed: widget.onDone,
              child: const Text("I'll check my bookings later"),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
