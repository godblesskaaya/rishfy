import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../data/models/route_models.dart';
import '../../domain/entities/route_entity.dart';
import '../providers/route_provider.dart';

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

  Future<void> _search() async {
    final String origin = _originCtrl.text.trim();
    final String dest = _destCtrl.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter origin and destination')),
      );
      return;
    }
    await ref.read(routeSearchProvider.notifier).search(
          RouteSearchParams(
            origin: origin,
            destination: dest,
            departureDate: _departureDate,
            seats: _seatCount,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final RouteSearchState searchState = ref.watch(routeSearchProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Search routes')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Origin + destination card
                  Container(
                    padding: const EdgeInsets.all(AppConstants.spaceMd),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusLg),
                    ),
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _originCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'From',
                            hintText: 'City name or lat,lng',
                            prefixIcon: Icon(Icons.my_location),
                            border: InputBorder.none,
                          ),
                        ),
                        const Divider(height: 1),
                        TextField(
                          controller: _destCtrl,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _search(),
                          decoration: const InputDecoration(
                            labelText: 'To',
                            hintText: 'City name or lat,lng',
                            prefixIcon: Icon(Icons.location_on),
                            border: InputBorder.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Date picker row
                  InkWell(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusLg),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _departureDate,
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 60)),
                      );
                      if (picked != null) {
                        setState(() => _departureDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceMd,
                        vertical: AppConstants.spaceSm + 4,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLg),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.calendar_today,
                              color:
                                  Theme.of(context).colorScheme.primary,
                              size: 20),
                          const SizedBox(width: 12),
                          Text(DateFormat('EEE, d MMM y')
                              .format(_departureDate)),
                          const Spacer(),
                          Text('Change',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Seat picker
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
                      Text('$_seatCount',
                          style: Theme.of(context).textTheme.titleMedium),
                      IconButton(
                        onPressed:
                            _seatCount < AppConstants.maxSeatsPerBooking
                                ? () => setState(() => _seatCount++)
                                : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  PrimaryButton(
                    label: 'Search',
                    icon: Icons.search,
                    loading: searchState.isLoading,
                    onPressed: searchState.isLoading ? null : _search,
                  ),

                  if (searchState.error != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      searchState.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),

            // Results
            if (searchState.results.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: searchState.results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int i) {
                    return _RouteCard(route: searchState.results[i]);
                  },
                ),
              )
            else if (!searchState.isLoading &&
                searchState.params != null &&
                searchState.results.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No routes found. Try different dates.'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route});

  final RouteEntity route;

  @override
  Widget build(BuildContext context) {
    final String price =
        'TZS ${NumberFormat('#,###').format(route.pricePerSeatTzs)}';
    final String time =
        DateFormat('HH:mm').format(route.departureDatetime.toLocal());

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        onTap: () => context.push('/routes/${route.routeId}'),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${route.originName} → ${route.destinationName}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(price,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  const Icon(Icons.access_time, size: 14),
                  const SizedBox(width: 4),
                  Text(time),
                  const SizedBox(width: 16),
                  const Icon(Icons.event_seat, size: 14),
                  const SizedBox(width: 4),
                  Text('${route.availableSeats} seats left'),
                  if (route.driverRating != null) ...<Widget>[
                    const SizedBox(width: 16),
                    const Icon(Icons.star, size: 14, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(route.driverRating!.toStringAsFixed(1)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                route.vehicleModel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
