import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';

/// Displays a single route with driver profile, pickup/dropoff details, and
/// the "Book" CTA. Wire up in Sprint 2 with route-service GetRoute call.
class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({required this.routeId, super.key});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route details')),
      body: const Padding(
        padding: EdgeInsets.all(AppConstants.spaceLg),
        child: Center(
          child: Text(
            'Route detail — wire up in Sprint 2\n\n'
            'Fetch via route-service GetRoute(routeId)\n'
            'Show: driver profile, vehicle, waypoints, map preview, price',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: PrimaryButton(
            label: 'Book this route',
            onPressed: () => context.push(
              '/bookings/create',
              extra: <String, dynamic>{'routeId': routeId},
            ),
          ),
        ),
      ),
    );
  }
}
