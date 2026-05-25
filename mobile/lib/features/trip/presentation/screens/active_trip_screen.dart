import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';

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
  bool _driverBroadcastRequested = false;
  bool _passengerTrackingRequested = false;
  String? _lastActionFeedback;

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _panToDriver(DriverLocationUpdate update) {
    if (!_followDriver) return;
    final Future<void>? animation = _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(update.lat, update.lng)),
    );
    if (animation != null) {
      unawaited(animation);
    }
  }

  void _frameTripContext(BookingEntity booking, DriverTrackingState tracking) {
    if (!_followDriver) return;
    final DriverLocationUpdate? update = tracking.latest;
    if (_mapController == null || update == null) {
      return;
    }
    final List<double> lats = <double>[update.lat];
    final List<double> lngs = <double>[update.lng];
    final double? targetLat = booking.isPrePickupJourney
        ? booking.resolvedPickupLat
        : booking.resolvedDropoffLat;
    final double? targetLng = booking.isPrePickupJourney
        ? booking.resolvedPickupLng
        : booking.resolvedDropoffLng;
    if (targetLat != null && targetLng != null) {
      lats.add(targetLat);
      lngs.add(targetLng);
    }
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        lats.reduce((double a, double b) => a < b ? a : b) - 0.005,
        lngs.reduce((double a, double b) => a < b ? a : b) - 0.005,
      ),
      northeast: LatLng(
        lats.reduce((double a, double b) => a > b ? a : b) + 0.005,
        lngs.reduce((double a, double b) => a > b ? a : b) + 0.005,
      ),
    );
    unawaited(_mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final String role = ref.watch(activeRoleProvider);
    final bool isDriver = role == 'driver';
    final AsyncValue<BookingEntity> asyncBooking =
        ref.watch(bookingDetailProvider(widget.bookingId));
    final DriverTrackingState tracking =
        ref.watch(driverTrackingProvider(widget.bookingId));
    final TripActionState actionState = ref.watch(journeyActionProvider);

    ref.listen<TripActionState>(journeyActionProvider,
        (TripActionState? previous, TripActionState next) async {
      final String feedbackKey = '${next.status}:${next.action}:${next.error}';
      if (_lastActionFeedback == feedbackKey) {
        return;
      }
      _lastActionFeedback = feedbackKey;

      if (next.status == TripActionStatus.success && mounted) {
        final String actionLabel = next.action ?? 'journey action';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_capitalize(actionLabel)} updated.')),
        );

        if (actionLabel == 'drop off passenger' ||
            actionLabel == 'complete trip' ||
            actionLabel == 'mark no-show' ||
            actionLabel == 'finish journey') {
          await ref.read(driverBroadcastProvider.notifier).stopStreaming();
          if (!mounted) {
            return;
          }
          if (actionLabel == 'finish journey' && !isDriver) {
            GoRouter.of(this.context).go('/bookings/${widget.bookingId}');
          } else if (isDriver) {
            GoRouter.of(this.context).go('/bookings');
          }
        } else if ((actionLabel == 'start drive to pickup' ||
                actionLabel == 'board passenger') &&
            mounted &&
            isDriver &&
            !_driverBroadcastRequested) {
          _driverBroadcastRequested = true;
          final BookingEntity updatedBooking =
              await ref.read(bookingDetailProvider(widget.bookingId).future);
          await ref
              .read(driverBroadcastProvider.notifier)
              .startStreaming(
                bookingId: updatedBooking.bookingId,
                tripId: updatedBooking.tripId,
              );
        }
      } else if (next.status == TripActionStatus.failed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error ?? 'Could not update trip state.')),
        );
      }
    });

    return asyncBooking.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, _) => Scaffold(
        appBar: AppBar(title: const Text('Trip')),
        body: Center(child: Text('Error: $error')),
      ),
      data: (BookingEntity booking) {
        final RouteEntity? route = booking.routePolyline == null
            ? ref.watch(routeDetailProvider(booking.routeId)).valueOrNull
            : null;

        if (booking.driverId != null) {
          ref
              .read(driverTrackingProvider(widget.bookingId).notifier)
              .seedFromBooking(booking);
        }

        if (isDriver &&
            booking.isJourneyActive &&
            booking.effectiveJourneyState != 'confirmed' &&
            !booking.isCompleted &&
            !_driverBroadcastRequested) {
          _driverBroadcastRequested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(
              ref
                  .read(driverBroadcastProvider.notifier)
                  .startStreaming(
                    bookingId: booking.bookingId,
                    tripId: booking.tripId,
                  ),
            );
          });
        }

        if (!isDriver &&
            booking.driverId != null &&
            booking.isJourneyTrackable &&
            !booking.isCompleted &&
            !_passengerTrackingRequested) {
          _passengerTrackingRequested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(
              ref
                  .read(driverTrackingProvider(widget.bookingId).notifier)
                  .connect(booking.driverId!),
            );
          });
        }

        if (tracking.latest != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _panToDriver(tracking.latest!);
            _frameTripContext(booking, tracking);
          });
        }

        return isDriver
            ? _buildDriverView(context, booking, tracking, route, actionState)
            : _buildPassengerView(
                context,
                booking,
                tracking,
                route,
                actionState,
              );
      },
    );
  }

  Widget _buildPassengerView(
    BuildContext context,
    BookingEntity booking,
    DriverTrackingState tracking,
    RouteEntity? route,
    TripActionState actionState,
  ) {
    final DriverLocationUpdate? driverUpdate = tracking.latest;
    final LatLng initialPosition = _initialCameraTarget(booking, tracking);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your trip'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.circle,
              size: 12,
              color: tracking.isConnected ? Colors.green : Colors.red,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            tooltip: 'Emergency',
            onPressed: () => unawaited(showEmergencyDialog(context)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Stack(
              children: <Widget>[
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: initialPosition, zoom: 14),
                  onMapCreated: _onMapCreated,
                  markers: _buildMarkers(booking, tracking, false),
                  polylines: _buildPolylines(booking, tracking, route),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onCameraMoveStarted: () =>
                      setState(() => _followDriver = false),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _TripMapOverlay(
                    booking: booking,
                    update: tracking.latest,
                    isDriver: false,
                  ),
                ),
                if (!_followDriver && driverUpdate != null)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter_trip',
                      onPressed: () {
                        setState(() => _followDriver = true);
                        _panToDriver(driverUpdate);
                      },
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                if (!tracking.isConnected && booking.isJourneyActive)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Reconnecting to live driver location...',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
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
              child: _PassengerJourneyPanel(
                booking: booking,
                tracking: tracking,
                actionState: actionState,
                onCompleteJourney: () => ref
                    .read(journeyActionProvider.notifier)
                    .completeJourney(widget.bookingId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverView(
    BuildContext context,
    BookingEntity booking,
    DriverTrackingState tracking,
    RouteEntity? route,
    TripActionState actionState,
  ) {
    final LatLng initialPosition = _initialCameraTarget(booking, tracking);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver trip'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            tooltip: 'Emergency',
            onPressed: () => unawaited(showEmergencyDialog(context)),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: initialPosition, zoom: 15),
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _buildMarkers(booking, tracking, true),
            polylines: _buildPolylines(booking, tracking, route),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _TripMapOverlay(
              booking: booking,
              update: tracking.latest,
              isDriver: true,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DriverJourneySheet(
              booking: booking,
              liveUpdate: tracking.latest,
              actionState: actionState,
              onStart: () => ref
                  .read(journeyActionProvider.notifier)
                  .start(widget.bookingId),
              onArrive: () => ref
                  .read(journeyActionProvider.notifier)
                  .arrivePickup(widget.bookingId),
              onBoard: () => ref
                  .read(journeyActionProvider.notifier)
                  .boardPassenger(widget.bookingId),
              onDropoff: () => ref
                  .read(journeyActionProvider.notifier)
                  .dropoffPassenger(widget.bookingId),
              onNoShow: () => _markNoShow(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markNoShow() async {
    final TextEditingController controller = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Mark no-show'),
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
            child: const Text('Mark no-show'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) {
      return;
    }
    await ref
        .read(journeyActionProvider.notifier)
        .markNoShow(widget.bookingId, reason: reason);
  }

  LatLng _initialCameraTarget(
    BookingEntity booking,
    DriverTrackingState tracking,
  ) {
    final DriverLocationUpdate? latest = tracking.latest;
    if (latest != null) {
      return LatLng(latest.lat, latest.lng);
    }
    if (booking.driverLat != null && booking.driverLng != null) {
      return LatLng(booking.driverLat!, booking.driverLng!);
    }
    if (booking.resolvedPickupLat != null &&
        booking.resolvedPickupLng != null) {
      return LatLng(booking.resolvedPickupLat!, booking.resolvedPickupLng!);
    }
    if (booking.resolvedDropoffLat != null &&
        booking.resolvedDropoffLng != null) {
      return LatLng(booking.resolvedDropoffLat!, booking.resolvedDropoffLng!);
    }
    return const LatLng(-6.3690, 34.8888);
  }

  Set<Marker> _buildMarkers(
    BookingEntity booking,
    DriverTrackingState tracking,
    bool isDriver,
  ) {
    final Set<Marker> markers = <Marker>{};
    final DriverLocationUpdate? latest = tracking.latest;
    final double? driverLat = latest?.lat ?? booking.driverLat;
    final double? driverLng = latest?.lng ?? booking.driverLng;
    final double driverHeading = latest?.heading ?? booking.driverHeading ?? 0;

    if (driverLat != null && driverLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(driverLat, driverLng),
          rotation: driverHeading,
          zIndex: 3,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: isDriver ? 'Your vehicle' : 'Driver',
            snippet: booking.driverName ?? '',
          ),
        ),
      );
    }

    if (booking.resolvedPickupLat != null &&
        booking.resolvedPickupLng != null) {
      final bool isActivePickup = booking.isPrePickupJourney;
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(
            booking.resolvedPickupLat!,
            booking.resolvedPickupLng!,
          ),
          zIndex: isActivePickup ? 2 : 1,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isActivePickup
                ? BitmapDescriptor.hueGreen
                : BitmapDescriptor.hueYellow,
          ),
          infoWindow: InfoWindow(title: booking.pickupDisplayName),
        ),
      );
    }

    if (booking.resolvedDropoffLat != null &&
        booking.resolvedDropoffLng != null) {
      final bool isActiveDropoff = !booking.isPrePickupJourney;
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(
            booking.resolvedDropoffLat!,
            booking.resolvedDropoffLng!,
          ),
          zIndex: isActiveDropoff ? 2 : 1,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isActiveDropoff
                ? BitmapDescriptor.hueRed
                : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(title: booking.dropoffDisplayName),
        ),
      );
    }

    final bool hasSeparateDestination = booking.destinationLat != null &&
        booking.destinationLng != null &&
        (booking.destinationLat != booking.resolvedDropoffLat ||
            booking.destinationLng != booking.resolvedDropoffLng);
    if (hasSeparateDestination) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(booking.destinationLat!, booking.destinationLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'Final destination'),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines(
    BookingEntity booking,
    DriverTrackingState tracking,
    RouteEntity? route,
  ) {
    final Set<Polyline> polylines = <Polyline>{};

    if (tracking.history.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('trail'),
          points: tracking.history
              .map((DriverLocationUpdate update) =>
                  LatLng(update.lat, update.lng))
              .toList(),
          color: Colors.blue.withValues(alpha: 0.7),
          width: 4,
          patterns: <PatternItem>[PatternItem.dash(12), PatternItem.gap(6)],
        ),
      );
    }

    final String? encodedPolyline =
        booking.routePolyline ?? route?.encodedPolyline;
    if (encodedPolyline != null && encodedPolyline.isNotEmpty) {
      try {
        final List<List<num>> coords = decodePolyline(encodedPolyline);
        if (coords.length >= 2) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: coords
                  .map((List<num> point) =>
                      LatLng(point[0].toDouble(), point[1].toDouble()))
                  .toList(),
              color: Colors.blueGrey.withValues(alpha: 0.45),
              width: 5,
            ),
          );
          final double? targetLat = booking.isPrePickupJourney
              ? booking.resolvedPickupLat
              : booking.resolvedDropoffLat;
          final double? targetLng = booking.isPrePickupJourney
              ? booking.resolvedPickupLng
              : booking.resolvedDropoffLng;
          final DriverLocationUpdate? latest = tracking.latest;
          if (latest != null && targetLat != null && targetLng != null) {
            polylines.add(
              Polyline(
                polylineId: const PolylineId('active_leg'),
                points: <LatLng>[
                  LatLng(latest.lat, latest.lng),
                  LatLng(targetLat, targetLng),
                ],
                color: Colors.blue,
                width: 6,
                patterns: const <PatternItem>[
                  PatternItem.dash(20),
                  PatternItem.gap(10),
                ],
              ),
            );
          }
        }
      } catch (_) {
        // Keep the trip screen usable even if the backend route polyline is malformed.
      }
    }

    return polylines;
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _PassengerJourneyPanel extends StatelessWidget {
  const _PassengerJourneyPanel({
    required this.booking,
    required this.tracking,
    required this.actionState,
    required this.onCompleteJourney,
  });

  final BookingEntity booking;
  final DriverTrackingState tracking;
  final TripActionState actionState;
  final VoidCallback onCompleteJourney;

  @override
  Widget build(BuildContext context) {
    final DriverLocationUpdate? update = tracking.latest;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<Widget> details = <Widget>[
      Row(
        children: <Widget>[
          _StatusChip(
            label: booking.journeyLabel,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.directions_car, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              booking.driverName ?? 'Your driver',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (booking.vehiclePlate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                booking.vehiclePlate!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        booking.isPrePickupJourney
            ? 'Pickup in progress'
            : booking.isPostDropoffJourney
                ? 'Arrival in progress'
                : 'Ride in progress',
        style:
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(_journeyMessage(booking)),
      const SizedBox(height: 12),
      _JourneyPhaseStrip(state: booking.effectiveJourneyState),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'What to do now',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _nextPassengerAction(booking),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _InfoRow(
        icon: Icons.pin_drop_outlined,
        label: booking.isPrePickupJourney ? 'Pickup' : 'Drop-off',
        value: booking.isPrePickupJourney
            ? booking.pickupDisplayName
            : booking.dropoffDisplayName,
      ),
    ];

    if (booking.isPrePickupJourney &&
        (booking.pickupWalkingDistance != null ||
            booking.pickupWalkingTime != null)) {
      details.add(
        _InfoRow(
          icon: Icons.directions_walk,
          label: 'Walk to pickup',
          value: _formatWalk(
            booking.pickupWalkingDistance,
            booking.pickupWalkingTime,
          ),
        ),
      );
    }

    if (booking.isPostDropoffJourney &&
        (booking.dropoffWalkingDistance != null ||
            booking.dropoffWalkingTime != null)) {
      details.add(
        _InfoRow(
          icon: Icons.directions_walk,
          label: 'Final walk',
          value: _formatWalk(
            booking.dropoffWalkingDistance,
            booking.dropoffWalkingTime,
          ),
        ),
      );
    }

    if (booking.estimatedPickupTime != null && booking.isPrePickupJourney) {
      details.add(
        _InfoRow(
          icon: Icons.event_available,
          label: 'Suggested pickup',
          value: _formatDateTime(booking.estimatedPickupTime!),
        ),
      );
    }

    final int? eta = booking.isPrePickupJourney
        ? (update?.etaToPickupSeconds ?? booking.etaToPickupSeconds)
        : (update?.etaToDropoffSeconds ?? booking.etaToDropoffSeconds);
    if (eta != null) {
      details.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _KpiPill(
              icon: Icons.schedule,
              label: 'ETA',
              value:
                  '${_formatEta(eta)}${booking.etaApproximate == true ? ' approx.' : ''}',
            ),
            if (update?.distanceToActiveStopMeters != null)
              _KpiPill(
                icon: Icons.route,
                label: booking.isPrePickupJourney
                    ? 'Distance'
                    : 'Remaining',
                value: _formatDistance(update!.distanceToActiveStopMeters!),
              ),
          ],
        ),
      );
    }

    if (update?.distanceToActiveStopMeters != null && eta == null) {
      details.add(
        _InfoRow(
          icon: Icons.route,
          label: booking.isPrePickupJourney
              ? 'Distance to pickup'
              : 'Distance to drop-off',
          value: _formatDistance(update!.distanceToActiveStopMeters!),
        ),
      );
    }

    if (update?.remainingRouteFraction != null) {
      details.add(
        _KpiPill(
          icon: Icons.timeline,
          label: 'Trip progress',
          value: _formatProgress(update!.remainingRouteFraction!),
        ),
      );
    }

    if (booking.etaStale == true) {
      details.add(
        const _InfoRow(
          icon: Icons.warning_amber_rounded,
          label: 'ETA quality',
          value: 'Driver ETA is stale. Keep following live location updates.',
        ),
      );
    }

    if (update != null) {
      details.add(
        _InfoRow(
          icon: Icons.update,
          label: 'Driver update',
          value: _timeAgo(update.timestamp),
        ),
      );
      details.add(
        _InfoRow(
          icon: Icons.speed,
          label: 'Speed',
          value: '${update.speedKmh.toStringAsFixed(0)} km/h',
        ),
      );
    }

    if (booking.canParticipantCompleteJourney) {
      details.add(const SizedBox(height: 12));
      details.add(
        PrimaryButton(
          label: 'Finish journey',
          loading: actionState.status == TripActionStatus.loading,
          onPressed: actionState.status == TripActionStatus.loading
              ? null
              : onCompleteJourney,
        ),
      );
    } else if (booking.isCompleted) {
      details.add(const SizedBox(height: 12));
      details.add(
        PrimaryButton(
          label: 'Open booking summary',
          onPressed: () => context.push('/bookings/${booking.bookingId}'),
        ),
      );
    } else if (!booking.isJourneyActive &&
        booking.effectiveJourneyState == 'confirmed') {
      details.add(const SizedBox(height: 12));
      details.add(
        PrimaryButton(
          label: 'Back to booking details',
          onPressed: () => context.push('/bookings/${booking.bookingId}'),
        ),
      );
    }

    if (actionState.status == TripActionStatus.loading) {
      details.add(const SizedBox(height: 12));
      details.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Text(
            'Updating trip state...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: details,
    );
  }

  String _journeyMessage(BookingEntity booking) {
    switch (booking.effectiveJourneyState) {
      case 'confirmed':
        return 'Your booking is confirmed. Head to the suggested pickup point before the driver arrives.';
      case 'walking_to_pickup':
        return 'Walk to the suggested pickup point so you are ready for boarding.';
      case 'waiting_for_driver':
        return 'Stay at the pickup point and keep live driver updates visible.';
      case 'driver_approaching':
        return 'Your driver is getting close to the pickup point.';
      case 'driver_arrived':
        return 'Your driver has reached the pickup point. Meet them now.';
      case 'boarded':
      case 'in_transit':
      case 'approaching_dropoff':
        return 'You are on the fixed route. Watch the drop-off marker and ETA.';
      case 'dropped_off':
      case 'walking_to_destination':
        return 'You have exited the vehicle. Continue to your destination from the drop-off point.';
      case 'completed':
        return 'Your trip is complete. You can review the booking summary and rate the ride.';
      case 'no_show':
        return 'This trip was marked as a no-show.';
      case 'cancelled':
        return 'This trip is no longer active.';
      default:
        return 'We are keeping the latest trip context synced for you.';
    }
  }

  String _nextPassengerAction(BookingEntity booking) {
    switch (booking.effectiveJourneyState) {
      case 'confirmed':
      case 'walking_to_pickup':
        return 'Walk to ${booking.pickupDisplayName} and keep your phone nearby for live driver updates.';
      case 'waiting_for_driver':
        return 'Wait at ${booking.pickupDisplayName} and watch for the driver approaching.';
      case 'driver_approaching':
        return 'Move to the curb or meeting point at ${booking.pickupDisplayName}.';
      case 'driver_arrived':
        return 'Meet the driver now and confirm the vehicle plate before boarding.';
      case 'boarded':
      case 'in_transit':
        return 'Stay onboard and track progress to ${booking.dropoffDisplayName}.';
      case 'approaching_dropoff':
        return 'Get ready to alight at ${booking.dropoffDisplayName}.';
      case 'dropped_off':
      case 'walking_to_destination':
        return 'Continue the final walk to your destination, then finish the journey here.';
      case 'completed':
        return 'Open your booking summary to review or rate the trip.';
      default:
        return 'Open the booking summary if you need more trip details.';
    }
  }

  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${(seconds / 60).ceil()}m';
  }

  String _formatDistance(int meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '$meters m';
  }

  String _formatProgress(double remainingFraction) {
    final int percent = ((1 - remainingFraction).clamp(0, 1) * 100).round();
    return '$percent% complete';
  }

  String _formatWalk(int? distanceMeters, int? timeSeconds) {
    final List<String> parts = <String>[];
    if (distanceMeters != null) {
      parts.add('${distanceMeters}m');
    }
    if (timeSeconds != null) {
      parts.add('${(timeSeconds / 60).ceil()} min');
    }
    return parts.isEmpty ? 'Pending' : parts.join(' • ');
  }

  String _formatDateTime(DateTime value) {
    final DateTime local = value.toLocal();
    final String hour = local.hour.toString().padLeft(2, '0');
    final String minute = local.minute.toString().padLeft(2, '0');
    final String day = local.day.toString().padLeft(2, '0');
    final String month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  String _timeAgo(DateTime timestamp) {
    final int seconds = DateTime.now().difference(timestamp).inSeconds;
    if (seconds < 60) {
      return '${seconds}s ago';
    }
    return '${(seconds / 60).floor()}m ago';
  }
}

class _TripMapOverlay extends StatelessWidget {
  const _TripMapOverlay({
    required this.booking,
    required this.update,
    required this.isDriver,
  });

  final BookingEntity booking;
  final DriverLocationUpdate? update;
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int? eta = booking.isPrePickupJourney
        ? (update?.etaToPickupSeconds ?? booking.etaToPickupSeconds)
        : (update?.etaToDropoffSeconds ?? booking.etaToDropoffSeconds);
    final String stopLabel = booking.isPrePickupJourney
        ? booking.pickupDisplayName
        : booking.dropoffDisplayName;

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      color: scheme.surface.withOpacity(0.96),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                booking.isPrePickupJourney ? Icons.pin_drop_outlined : Icons.flag_outlined,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isDriver ? booking.nextDriverActionLabel : booking.journeyLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stopLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (eta != null)
              Text(
                _formatEta(eta),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DriverJourneySheet extends StatelessWidget {
  const _DriverJourneySheet({
    required this.booking,
    required this.liveUpdate,
    required this.actionState,
    required this.onStart,
    required this.onArrive,
    required this.onBoard,
    required this.onDropoff,
    required this.onNoShow,
  });

  final BookingEntity booking;
  final DriverLocationUpdate? liveUpdate;
  final TripActionState actionState;
  final VoidCallback onStart;
  final VoidCallback onArrive;
  final VoidCallback onBoard;
  final VoidCallback onDropoff;
  final VoidCallback onNoShow;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isLoading = actionState.status == TripActionStatus.loading;
    final int? eta = booking.isPrePickupJourney
        ? (liveUpdate?.etaToPickupSeconds ?? booking.etaToPickupSeconds)
        : (liveUpdate?.etaToDropoffSeconds ?? booking.etaToDropoffSeconds);

    String nextActionLabel() {
      return booking.nextDriverActionLabel;
    }

    VoidCallback? primaryAction() {
      if (isLoading) return null;
      if (booking.canDriverStartTrip) return onStart;
      if (booking.canDriverMarkArrived) return onArrive;
      if (booking.canDriverMarkBoarded) return onBoard;
      if (booking.canDriverMarkDroppedOff) return onDropoff;
      return null;
    }

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
                Icon(Icons.alt_route, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    booking.journeyLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceMd),
            _JourneyPhaseStrip(
              state: booking.effectiveJourneyState,
              isDriver: true,
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Rider',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    booking.passengerDisplayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${booking.seatCount} seat${booking.seatCount == 1 ? '' : 's'} booked'
                    '${booking.confirmationCode != null ? ' • Code ${booking.confirmationCode}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Operational focus',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _driverSheetHint(booking),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Text(
              '${booking.originName ?? 'Route'} -> ${booking.destinationName ?? ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppConstants.spaceSm),
            _InfoRow(
              icon: Icons.pin_drop_outlined,
              label: 'Pickup',
              value: booking.pickupDisplayName,
            ),
            _InfoRow(
              icon: Icons.flag_outlined,
              label: 'Drop-off',
              value: booking.dropoffDisplayName,
            ),
            if (eta != null)
              _InfoRow(
                icon: Icons.schedule,
                label: booking.isPrePickupJourney ? 'ETA to pickup' : 'ETA',
                value:
                    '${_formatEta(eta)}${booking.etaApproximate == true ? ' approx.' : ''}',
              ),
            if (liveUpdate?.distanceToActiveStopMeters != null)
              _InfoRow(
                icon: Icons.route,
                label: booking.isPrePickupJourney
                    ? 'Distance to pickup'
                    : 'Distance to drop-off',
                value: _formatDistance(liveUpdate!.distanceToActiveStopMeters!),
              ),
            if (liveUpdate?.remainingRouteFraction != null)
              _InfoRow(
                icon: Icons.timeline,
                label: 'Trip progress',
                value: _formatProgress(liveUpdate!.remainingRouteFraction!),
              ),
            if (liveUpdate != null)
              _InfoRow(
                icon: Icons.update,
                label: 'Last live update',
                value: _timeAgo(liveUpdate!.timestamp),
              ),
            if (liveUpdate == null &&
                booking.driverLat != null &&
                booking.driverLng != null &&
                booking.driverLocationUpdatedAt != null)
              _InfoRow(
                icon: Icons.update,
                label: 'Last live update',
                value: _timeAgo(booking.driverLocationUpdatedAt!),
              ),
            if (booking.driverLat != null &&
                booking.driverLng != null &&
                booking.etaStale == true)
              const _InfoRow(
                icon: Icons.warning_amber_rounded,
                label: 'ETA quality',
                value: 'Live tracking is active, but ETA confidence is low right now.',
              ),
            const SizedBox(height: AppConstants.spaceMd),
            Text(
              'Next action: ${nextActionLabel()}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            if (booking.canDriverMarkNoShow) ...<Widget>[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : onNoShow,
                  icon: const Icon(Icons.person_off_outlined),
                  label: const Text('Mark no-show'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (primaryAction() != null)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: primaryAction(),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          nextActionLabel(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              )
            else if (booking.isCompleted)
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Back to bookings',
                  onPressed: () => context.go('/bookings'),
                ),
              )
            else if (booking.canParticipantCompleteJourney)
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Passenger on final walk',
                  onPressed: () => context.go('/bookings'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _driverSheetHint(BookingEntity booking) {
    if (booking.canDriverStartTrip) {
      return 'Start the drive to ${booking.pickupDisplayName} and keep live tracking active while you approach the rider.';
    }
    if (booking.canDriverMarkArrived) {
      return 'Reach ${booking.pickupDisplayName} and confirm arrival once the rider can identify you at the pickup point.';
    }
    if (booking.canDriverMarkBoarded) {
      return 'The rider is at the pickup point. Confirm boarding only after they are seated and ready to depart.';
    }
    if (booking.canDriverMarkDroppedOff) {
      return 'Follow the live trip route to ${booking.dropoffDisplayName} and confirm drop-off once the rider has alighted.';
    }
    if (booking.canParticipantCompleteJourney) {
      return 'Your driving portion is complete. The rider is finishing the last walking segment on foot.';
    }
    return 'No operational action is pending for this booking.';
  }

  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${(seconds / 60).ceil()}m';
  }

  String _formatDistance(int meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '$meters m';
  }

  String _formatProgress(double remainingFraction) {
    final int percent = ((1 - remainingFraction).clamp(0, 1) * 100).round();
    return '$percent% complete';
  }

  String _timeAgo(DateTime timestamp) {
    final int seconds = DateTime.now().difference(timestamp).inSeconds;
    if (seconds < 60) {
      return '${seconds}s ago';
    }
    return '${(seconds / 60).floor()}m ago';
  }
}

class _JourneyPhaseStrip extends StatelessWidget {
  const _JourneyPhaseStrip({
    required this.state,
    this.isDriver = false,
  });

  final String state;
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int activeIndex = _activeIndex(state);
    final List<({String key, String label})> steps = isDriver
        ? const <({String key, String label})>[
            (key: 'confirmed', label: 'To pickup'),
            (key: 'driver_arrived', label: 'At pickup'),
            (key: 'in_transit', label: 'On route'),
            (key: 'walking_to_destination', label: 'Drop-off'),
            (key: 'completed', label: 'Done'),
          ]
        : const <({String key, String label})>[
            (key: 'confirmed', label: 'Pickup'),
            (key: 'driver_arrived', label: 'Arrived'),
            (key: 'in_transit', label: 'Onboard'),
            (key: 'walking_to_destination', label: 'Final walk'),
            (key: 'completed', label: 'Done'),
          ];

    return Row(
      children: List<Widget>.generate(steps.length, (int index) {
        final bool completed = index < activeIndex;
        final bool active = index == activeIndex;
        final Color color =
            completed || active ? scheme.primary : scheme.outlineVariant;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == steps.length - 1 ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  steps[index].label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: active || completed
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  int _activeIndex(String state) {
    switch (state) {
      case 'confirmed':
      case 'walking_to_pickup':
      case 'waiting_for_driver':
      case 'driver_approaching':
        return 0;
      case 'driver_arrived':
        return 1;
      case 'boarded':
      case 'in_transit':
      case 'approaching_dropoff':
        return 2;
      case 'dropped_off':
      case 'walking_to_destination':
        return 3;
      case 'completed':
        return 4;
      case 'cancelled':
      case 'no_show':
        return isDriver ? 0 : 1;
      default:
        return 0;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
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

class _KpiPill extends StatelessWidget {
  const _KpiPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.75),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
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
