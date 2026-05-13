import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/active_role_provider.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../bookings/domain/entities/booking_entity.dart';
import '../../../bookings/presentation/providers/booking_provider.dart';
import '../../../home/presentation/screens/shell_screen.dart';
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
    if (loc == null) return <Marker>{};
    return <Marker>{
      Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(loc.lat, loc.lng),
        rotation: loc.heading,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(title: 'Driver', snippet: booking.driverName ?? ''),
      ),
    };
  }

  Set<Polyline> _buildTrail(List<DriverLocationUpdate> history) {
    if (history.length < 2) return <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('trail'),
        points: history.map((DriverLocationUpdate u) => LatLng(u.lat, u.lng)).toList(),
        color: Colors.blue.withValues(alpha: 0.6),
        width: 3,
        patterns: <PatternItem>[PatternItem.dash(12), PatternItem.gap(6)],
      ),
    };
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
        data: (BookingEntity booking) => _buildBody(context, booking, tracking),
      ),
    );
  }

  Widget _buildDriverView(BuildContext context, BookingEntity booking) {
    final TripActionState completeState = ref.watch(completeTripProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.directions_car, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Trip in progress',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            if (booking.originName != null) ...<Widget>[
              Text('Pickup', style: Theme.of(context).textTheme.labelMedium),
              Text(booking.originName!),
              const SizedBox(height: AppConstants.spaceMd),
            ],
            if (booking.destinationName != null) ...<Widget>[
              Text('Drop-off', style: Theme.of(context).textTheme.labelMedium),
              Text(booking.destinationName!),
              const SizedBox(height: AppConstants.spaceMd),
            ],
            const Spacer(),
            if (completeState.status == TripActionStatus.failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  completeState.error ?? 'Could not complete trip.',
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isCompleting
                    ? null
                    : () => ref
                        .read(completeTripProvider.notifier)
                        .complete(widget.bookingId),
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
                    : const Text('Complete Trip',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BookingEntity booking, DriverTrackingState tracking) {
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
                polylines: _buildTrail(tracking.history),
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
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
