import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';

/// Route search. Integrates with:
///   - Google Places Autocomplete for origin/destination fields
///   - route-service /api/v1/routes/search for results
///
/// Wire up in Sprint 2 when route-service search endpoint is live.
class RouteSearchScreen extends ConsumerStatefulWidget {
  const RouteSearchScreen({super.key});

  @override
  ConsumerState<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

class _RouteSearchScreenState extends ConsumerState<RouteSearchScreen> {
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  DateTime _departureDate = DateTime.now();
  int _seatCount = 1;

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search routes')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Origin + destination
              Container(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _originCtrl,
                      decoration: const InputDecoration(
                        labelText: 'From',
                        prefixIcon: Icon(Icons.my_location),
                        border: InputBorder.none,
                      ),
                    ),
                    const Divider(),
                    TextField(
                      controller: _destCtrl,
                      decoration: const InputDecoration(
                        labelText: 'To',
                        prefixIcon: Icon(Icons.location_on),
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Departure date + time
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMd,
                  vertical: AppConstants.spaceSm,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.calendar_today,
                        color: Theme.of(context).colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${_departureDate.day}/${_departureDate.month}/${_departureDate.year}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _departureDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setState(() => _departureDate = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Seats
              Row(
                children: <Widget>[
                  const Text('Seats'),
                  const Spacer(),
                  IconButton(
                    onPressed: _seatCount > 1
                        ? () => setState(() => _seatCount--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_seatCount'),
                  IconButton(
                    onPressed: _seatCount < AppConstants.maxSeatsPerBooking
                        ? () => setState(() => _seatCount++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),

              const Spacer(),
              PrimaryButton(
                label: 'Search',
                icon: Icons.search,
                onPressed: () {
                  // TODO(Godbless): Call route-service search API, push results screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Route search coming in Sprint 2'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
