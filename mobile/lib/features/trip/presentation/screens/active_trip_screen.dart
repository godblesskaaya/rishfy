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
            actionLabel == 'mark no-show') {
          await ref.read(driverBroadcastProvider.notifier).stopStreaming();
          if (!mounted) {
            return;
          }
          if (isDriver) {
            context.go('/bookings');
          }
        } else if (actionLabel == 'board passenger' &&
            mounted &&
            isDriver &&
            !_driverBroadcastRequested) {
          _driverBroadcastRequested = true;
          final BookingEntity updatedBooking =
              await ref.read(bookingDetailProvider(widget.bookingId).future);
          await ref
              .read(driverBroadcastProvider.notifier)
              .startStreaming(updatedBooking.journeyStreamId);
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
                  .startStreaming(booking.journeyStreamId),
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
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _panToDriver(tracking.latest!));
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
        title: const Text('Passenger trip'),
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
            left: 0,
            right: 0,
            bottom: 0,
            child: _DriverJourneySheet(
              booking: booking,
              actionState: actionState,
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: isDriver ? 'Your vehicle' : 'Driver',
            snippet: booking.driverName ?? '',
          ),
        ),
      );
    }

    if (booking.resolvedPickupLat != null &&
        booking.resolvedPickupLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(
            booking.resolvedPickupLat!,
            booking.resolvedPickupLng!,
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: booking.pickupDisplayName),
        ),
      );
    }

    if (booking.resolvedDropoffLat != null &&
        booking.resolvedDropoffLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(
            booking.resolvedDropoffLat!,
            booking.resolvedDropoffLng!,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
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
              color: Colors.grey.withValues(alpha: 0.55),
              width: 4,
            ),
          );
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
  });

  final BookingEntity booking;
  final DriverTrackingState tracking;
  final TripActionState actionState;

  @override
  Widget build(BuildContext context) {
    final DriverLocationUpdate? update = tracking.latest;
    final ThemeData theme = Theme.of(context);
    final List<Widget> details = <Widget>[
      Row(
        children: <Widget>[
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
        booking.journeyLabel,
        style:
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(_journeyMessage(booking)),
      const SizedBox(height: 12),
      _InfoRow(
        icon: Icons.pin_drop_outlined,
        label: booking.isPrePickupJourney ? 'Pickup' : 'Drop-off',
        value: booking.isPrePickupJourney
            ? booking.pickupDisplayName
            : booking.dropoffDisplayName,
      ),
    ];

    final int? eta = booking.isPrePickupJourney
        ? (update?.etaToPickupSeconds ?? booking.etaToPickupSeconds)
        : (update?.etaToDropoffSeconds ?? booking.etaToDropoffSeconds);
    if (eta != null) {
      details.add(
        _InfoRow(
          icon: Icons.schedule,
          label: 'ETA',
          value:
              '${_formatEta(eta)}${booking.etaApproximate == true ? ' approx.' : ''}',
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

    if (booking.isCompleted) {
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
        Text(
          'Updating trip state...',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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
      case 'walking_to_pickup':
      case 'waiting_for_driver':
        return 'Head to the suggested pickup point and keep an eye on driver updates.';
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

  String _formatEta(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${(seconds / 60).ceil()}m';
  }

  String _timeAgo(DateTime timestamp) {
    final int seconds = DateTime.now().difference(timestamp).inSeconds;
    if (seconds < 60) {
      return '${seconds}s ago';
    }
    return '${(seconds / 60).floor()}m ago';
  }
}

class _DriverJourneySheet extends StatelessWidget {
  const _DriverJourneySheet({
    required this.booking,
    required this.actionState,
    required this.onArrive,
    required this.onBoard,
    required this.onDropoff,
    required this.onNoShow,
  });

  final BookingEntity booking;
  final TripActionState actionState;
  final VoidCallback onArrive;
  final VoidCallback onBoard;
  final VoidCallback onDropoff;
  final VoidCallback onNoShow;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isLoading = actionState.status == TripActionStatus.loading;

    String nextActionLabel() {
      if (booking.canDriverMarkArrived) {
        return 'Arrive at pickup';
      }
      if (booking.canDriverMarkBoarded) {
        return 'Passenger boarded';
      }
      if (booking.canDriverMarkDroppedOff) {
        return 'Passenger dropped off';
      }
      if (booking.isCompleted) {
        return 'Trip completed';
      }
      return booking.journeyLabel;
    }

    VoidCallback? primaryAction() {
      if (isLoading) return null;
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
              ),
          ],
        ),
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
