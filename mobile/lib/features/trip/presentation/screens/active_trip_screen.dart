import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/active_role_provider.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../bookings/domain/entities/booking_entity.dart';
import '../../../bookings/presentation/providers/booking_provider.dart';
import '../../../home/presentation/screens/shell_screen.dart';
import '../../../routes/domain/entities/route_entity.dart';
import '../../../routes/presentation/providers/route_provider.dart';
import '../../data/models/location_models.dart';
import '../providers/trip_provider.dart';

class ActiveTripScreen extends ConsumerStatefulWidget {
  const ActiveTripScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
  GoogleMapController? _mapController;
  bool _followDriver = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final AsyncValue<BookingEntity> booking =
          ref.read(bookingDetailProvider(widget.bookingId));
      final String driverId =
          booking.valueOrNull?.driverId ?? '';
      ref
          .read(driverTrackingProvider(widget.bookingId).notifier)
          .connect(driverId);
    });
  }

  void _onMapCreated(GoogleMapController c) => _mapController = c;

  void _panToDriver(DriverLocationUpdate loc) {
    if (!_followDriver) return;
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(loc.lat, loc.lng)),
    );
  }

  Set<Marker> _buildMarkers(DriverLocationUpdate? loc, BookingEntity booking) {
    final Set<Marker> markers = <Marker>{};
    if (loc != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(loc.lat, loc.lng),
        rotation: loc.heading,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(title: 'Driver', snippet: booking.driverName ?? ''),
      ));
    }
    if (booking.pickupLat != null && booking.pickupLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(booking.pickupLat!, booking.pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: booking.suggestedPickupName ?? 'Your pickup',
        ),
      ));
    }
    if (booking.destinationLat != null && booking.destinationLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(booking.destinationLat!, booking.destinationLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Your dropoff'),
      ));
    }
    return markers;
  }

  Set<Polyline> _buildPolylines(
    List<DriverLocationUpdate> history,
    RouteEntity? route,
  ) {
    final Set<Polyline> polylines = <Polyline>{};

    // Driver trail
    if (history.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('trail'),
        points: history
            .map((DriverLocationUpdate u) => LatLng(u.lat, u.lng))
            .toList(),
        color: Colors.blue.withValues(alpha: 0.6),
        width: 3,
        patterns: <PatternItem>[PatternItem.dash(12), PatternItem.gap(6)],
      ));
    }

    // Planned route polyline (light grey, behind trail)
    if (route?.encodedPolyline != null &&
        route!.encodedPolyline!.isNotEmpty) {
      final List<List<num>> coords = decodePolyline(route.encodedPolyline!);
      if (coords.length >= 2) {
        polylines.add(Polyline(
          polylineId: const PolylineId('planned_route'),
          points: coords
              .map((List<num> p) => LatLng(p[0].toDouble(), p[1].toDouble()))
              .toList(),
          color: Colors.grey.withValues(alpha: 0.5),
          width: 3,
        ));
      }
    }

    return polylines;
  }

  Future<void> _triggerEmergency(BuildContext ctx) async {
    await showEmergencyDialog(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final String role = ref.watch(activeRoleProvider);
    final AsyncValue<BookingEntity> asyncBooking =
        ref.watch(bookingDetailProvider(widget.bookingId));
    final DriverTrackingState tracking =
        ref.watch(driverTrackingProvider(widget.bookingId));

    // Fetch route entity for polyline — routeId is known once booking loads.
    // Use a stable placeholder so ref.watch is always called unconditionally.
    final String routeId = asyncBooking.valueOrNull?.routeId ?? '';
    final RouteEntity? route = routeId.isNotEmpty
        ? ref.watch(routeDetailProvider(routeId)).valueOrNull
        : null;

    if (role == 'driver') {
      return asyncBooking.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (Object e, _) => Scaffold(
          appBar: AppBar(title: const Text('Active trip')),
          body: Center(child: Text('Error: $e')),
        ),
        data: (BookingEntity booking) => _buildDriverView(context, booking),
      );
    }

    if (tracking.latest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _panToDriver(tracking.latest!));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your trip'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.circle, size: 12,
                color: tracking.isConnected ? Colors.green : Colors.red),
          ),
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            tooltip: 'Emergency',
            onPressed: () => _triggerEmergency(context),
          ),
        ],
      ),
      body: asyncBooking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (BookingEntity booking) =>
            _buildBody(context, booking, tracking, route),
      ),
    );
  }

  Widget _buildDriverView(BuildContext context, BookingEntity booking) {
    final TripActionState completeState = ref.watch(completeTripProvider);
    final bool isCompleting = completeState.status == TripActionStatus.loading;

    ref.listen(completeTripProvider, (TripActionState? _, TripActionState next) {
      if (next.status == TripActionStatus.success) {
        ref.read(driverBroadcastProvider.notifier).stopStreaming();
        if (mounted) context.go('/bookings');
      } else if (next.status == TripActionStatus.failed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error ?? 'Could not complete trip.')),
        );
      }
    });

    final LatLng initial = booking.pickupLat != null && booking.pickupLng != null
        ? LatLng(booking.pickupLat!, booking.pickupLng!)
        : const LatLng(-6.3690, 34.8888);

    final Set<Marker> driverMarkers = <Marker>{
      if (booking.pickupLat != null && booking.pickupLng != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(booking.pickupLat!, booking.pickupLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: booking.suggestedPickupName ?? 'Passenger pickup',
          ),
        ),
      if (booking.destinationLat != null && booking.destinationLng != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(booking.destinationLat!, booking.destinationLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Dropoff'),
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active trip'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            tooltip: 'Emergency',
            onPressed: () => _triggerEmergency(context),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initial, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: driverMarkers,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _DriverTripBottomCard(
              booking: booking,
              isCompleting: isCompleting,
              error: completeState.status == TripActionStatus.failed
                  ? (completeState.error ?? 'Could not complete trip.')
                  : null,
              onComplete: () => ref
                  .read(completeTripProvider.notifier)
                  .complete(widget.bookingId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, BookingEntity booking, DriverTrackingState tracking, RouteEntity? route) {
    final DriverLocationUpdate? loc = tracking.latest;
    final LatLng initialPos =
        loc != null ? LatLng(loc.lat, loc.lng) : const LatLng(-6.3690, 34.8888);

    return Column(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Stack(
            children: <Widget>[
              GoogleMap(
                initialCameraPosition: CameraPosition(target: initialPos, zoom: 14),
                onMapCreated: _onMapCreated,
                markers: _buildMarkers(loc, booking),
                polylines: _buildPolylines(tracking.history, route),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                onCameraMoveStarted: () => setState(() => _followDriver = false),
              ),
              if (!_followDriver && loc != null)
                Positioned(
                  right: 16, bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'recenter',
                    onPressed: () {
                      setState(() => _followDriver = true);
                      _panToDriver(loc);
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
              if (!tracking.isConnected)
                Positioned(
                  top: 8, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Reconnecting...',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.directions_car, size: 18),
                    const SizedBox(width: 8),
                    Text(booking.driverName ?? 'Your driver',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (booking.vehiclePlate != null) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(booking.vehiclePlate!,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (booking.originName != null && booking.destinationName != null)
                  Text('${booking.originName} → ${booking.destinationName}'),
                if (booking.departureDatetime != null)
                  Text(DateFormat('EEE d MMM, HH:mm')
                      .format(booking.departureDatetime!.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall),
                if (loc != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.speed, size: 16),
                      const SizedBox(width: 4),
                      Text('${loc.speedKmh.toStringAsFixed(0)} km/h'),
                      const SizedBox(width: 16),
                      const Icon(Icons.update, size: 16),
                      const SizedBox(width: 4),
                      Text(_timeAgo(loc.timestamp)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                if (booking.status == 'completed')
                  PrimaryButton(
                    label: 'Rate your trip',
                    onPressed: () => _showRatingSheet(context, booking),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _timeAgo(DateTime t) {
    final int secs = DateTime.now().difference(t).inSeconds;
    if (secs < 60) return '${secs}s ago';
    return '${(secs / 60).floor()}m ago';
  }

  Future<void> _showRatingSheet(BuildContext ctx, BookingEntity booking) async {
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
      ),
      builder: (_) => _RatingSheet(
        bookingId: booking.bookingId,
        driverName: booking.driverName ?? 'your driver',
        onSubmitted: () {
          Navigator.pop(ctx);
          context.go('/bookings');
        },
      ),
    );
  }
}

// ─── Driver trip bottom card ──────────────────────────────────────────────────

class _DriverTripBottomCard extends StatelessWidget {
  const _DriverTripBottomCard({
    required this.booking,
    required this.isCompleting,
    required this.onComplete,
    this.error,
  });

  final BookingEntity booking;
  final bool isCompleting;
  final String? error;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppConstants.radiusXl),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppConstants.spaceLg,
          AppConstants.spaceMd,
          AppConstants.spaceLg,
          AppConstants.spaceLg + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                Icon(Icons.directions_car, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Trip in progress',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMd),
            if (booking.originName != null) ...<Widget>[
              Text('Pickup',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.outline,
                      )),
              Text(booking.originName!),
              const SizedBox(height: AppConstants.spaceSm),
            ],
            if (booking.destinationName != null) ...<Widget>[
              Text('Drop-off',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.outline,
                      )),
              Text(booking.destinationName!),
              const SizedBox(height: AppConstants.spaceMd),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isCompleting ? null : onComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                child: isCompleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Complete Trip',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Rating sheet ─────────────────────────────────────────────────────────────

class _RatingSheet extends ConsumerStatefulWidget {
  const _RatingSheet({
    required this.bookingId,
    required this.driverName,
    required this.onSubmitted,
  });
  final String bookingId;
  final String driverName;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<_RatingSheet> {
  int _rating = 0;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select a rating')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(bookingDataSourceProvider).rateTrip(
            bookingId: widget.bookingId,
            rating: _rating,
            comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
          );
      widget.onSubmitted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spaceLg,
        right: AppConstants.spaceLg,
        top: AppConstants.spaceLg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppConstants.spaceLg,
      ),
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
          Text('Rate your trip', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('How was your ride with ${widget.driverName}?'),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(5, (int i) {
              return GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber, size: 40,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comments (optional)',
              border: OutlineInputBorder(),
              hintText: 'How was the drive?',
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Submit rating',
            loading: _isLoading,
            onPressed: _isLoading ? null : _submit,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: widget.onSubmitted, child: const Text('Skip')),
        ],
      ),
    );
  }
}
