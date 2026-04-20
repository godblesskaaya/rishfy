import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';

/// Multi-step form for drivers to post a new route.
///  Step 1: Origin + destination
///  Step 2: Departure time + vehicle + available seats
///  Step 3: Price per seat + preferences (smoking, pets, music)
///  Step 4: Review + confirm
///
/// Wire up in Sprint 2 with route-service PostRoute call.
class PostRouteScreen extends ConsumerStatefulWidget {
  const PostRouteScreen({super.key});

  @override
  ConsumerState<PostRouteScreen> createState() => _PostRouteScreenState();
}

class _PostRouteScreenState extends ConsumerState<PostRouteScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a route')),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Stepper(
          currentStep: _step,
          onStepContinue: () {
            if (_step < 3) setState(() => _step++);
          },
          onStepCancel: () {
            if (_step > 0) setState(() => _step--);
          },
          steps: const <Step>[
            Step(
              title: Text('Route'),
              content: Text('Origin + destination with Google Places autocomplete'),
            ),
            Step(
              title: Text('Schedule'),
              content: Text('Departure date/time + vehicle + seats available'),
            ),
            Step(
              title: Text('Pricing'),
              content: Text('Price per seat + preferences'),
            ),
            Step(
              title: Text('Review'),
              content: Text('Confirm and post'),
            ),
          ],
        ),
      ),
    );
  }
}
