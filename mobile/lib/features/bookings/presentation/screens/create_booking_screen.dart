import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';

/// Confirm booking + choose payment method (M-Pesa/TigoPesa/Airtel).
/// Wire up in Sprint 3 with booking-service CreateBooking.
class CreateBookingScreen extends ConsumerStatefulWidget {
  const CreateBookingScreen({required this.routeId, super.key});

  final String routeId;

  @override
  ConsumerState<CreateBookingScreen> createState() =>
      _CreateBookingScreenState();
}

class _CreateBookingScreenState extends ConsumerState<CreateBookingScreen> {
  String _paymentMethod = 'mpesa';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm booking')),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Route: ${widget.routeId}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            Text('Payment method',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            RadioListTile<String>(
              title: const Text('M-Pesa'),
              value: 'mpesa',
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
            const Spacer(),
            PrimaryButton(
              label: 'Pay and book',
              onPressed: () {
                // TODO(Ezekiel): Call booking-service CreateBooking,
                // then handle mobile money payment initiation
              },
            ),
          ],
        ),
      ),
    );
  }
}
