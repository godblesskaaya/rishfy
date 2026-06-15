import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../bookings/domain/entities/booking_entity.dart';
import '../../domain/entities/route_entity.dart';
import '../providers/route_provider.dart';

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({required this.routeId, super.key});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? currentUserId = ref.watch(currentUserProvider)?.userId;
    final bool isOwnRouteCandidate = currentUserId != null;
    final AsyncValue<RouteEntity> asyncRoute =
        ref.watch(routeDetailProvider(routeId));
    final AsyncValue<DriverRouteOperations> asyncOperations =
        isOwnRouteCandidate
            ? ref.watch(driverRouteOperationsProvider(routeId))
            : const AsyncValue<DriverRouteOperations>.loading();

    return asyncRoute.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, _) => Scaffold(
        appBar: AppBar(title: const Text('Route details')),
        body: Center(child: Text('Failed to load route: $e')),
      ),
      data: (RouteEntity route) => _RouteDetailBody(
        route: asyncOperations.valueOrNull?.route ?? route,
        routeOperationsAsync: asyncOperations,
      ),
    );
  }
}

class _RouteDetailBody extends ConsumerStatefulWidget {
  const _RouteDetailBody({
    required this.route,
    required this.routeOperationsAsync,
  });

  final RouteEntity route;
  final AsyncValue<DriverRouteOperations> routeOperationsAsync;

  @override
  ConsumerState<_RouteDetailBody> createState() => _RouteDetailBodyState();
}

class _RouteDetailBodyState extends ConsumerState<_RouteDetailBody> {
  RouteEntity get route => widget.route;
  Position? _myPosition;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchMyPosition());
  }

  Future<void> _fetchMyPosition() async {
    try {
      final LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      if (mounted) {
        setState(() => _myPosition = pos);
      }
    } catch (_) {
      // Location unavailable — no marker shown.
    }
  }

  Set<Polyline> _buildPolylines() {
    final DriverRouteOperations? operations =
        widget.routeOperationsAsync.valueOrNull;
    if (route.encodedPolyline == null || route.encodedPolyline!.isEmpty) {
      return <Polyline>{};
    }
    final List<List<num>> coords = decodePolyline(route.encodedPolyline!);
    final List<LatLng> points = coords
        .map((List<num> point) =>
            LatLng(point[0].toDouble(), point[1].toDouble()))
        .toList();
    final Set<Polyline> polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route_base'),
        points: points,
        color: Colors.blueGrey.withOpacity(0.45),
        width: 5,
      ),
    };
    final DriverRouteRunStop? activeStop = operations?.activeStop;
    if (activeStop != null) {
      final BookingEntity? booking = _bookingForStop(operations, activeStop);
      final double? stopLat = activeStop.isPickup
          ? booking?.resolvedPickupLat
          : booking?.resolvedDropoffLat;
      final double? stopLng = activeStop.isPickup
          ? booking?.resolvedPickupLng
          : booking?.resolvedDropoffLng;
      if (_myPosition != null && stopLat != null && stopLng != null) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('active_guidance'),
            points: <LatLng>[
              LatLng(_myPosition!.latitude, _myPosition!.longitude),
              LatLng(stopLat, stopLng),
            ],
            color: Colors.blue,
            width: 6,
            patterns: <PatternItem>[
              PatternItem.dash(20),
              PatternItem.gap(10),
            ],
          ),
        );
      }
    }
    return polylines;
  }

  BookingEntity? _bookingForStop(
    DriverRouteOperations? operations,
    DriverRouteRunStop stop,
  ) {
    if (operations == null) return null;
    for (final BookingEntity booking in operations.bookings) {
      if (booking.bookingId == stop.bookingId) {
        return booking;
      }
    }
    return null;
  }

  Set<Marker> _buildMarkers() {
    final DriverRouteOperations? operations =
        widget.routeOperationsAsync.valueOrNull;
    final Map<String, BookingEntity> bookingsById = <String, BookingEntity>{
      for (final BookingEntity booking
          in operations?.bookings ?? <BookingEntity>[])
        booking.bookingId: booking,
    };
    final Set<Marker> markers = <Marker>{
      Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(route.originLat, route.originLng),
        infoWindow: InfoWindow(title: route.originName),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(route.destinationLat, route.destinationLng),
        infoWindow: InfoWindow(title: route.destinationName),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      ...route.waypoints.map(
        (RouteWaypoint waypoint) => Marker(
          markerId: MarkerId('wp_${waypoint.order}'),
          position: LatLng(waypoint.lat, waypoint.lng),
          infoWindow: InfoWindow(title: waypoint.name),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      ),
      if (_myPosition != null)
        Marker(
          markerId: const MarkerId('me'),
          position: LatLng(_myPosition!.latitude, _myPosition!.longitude),
          infoWindow: const InfoWindow(title: 'You are here'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };

    for (final DriverRouteRunStop stop
        in operations?.runStops ?? <DriverRouteRunStop>[]) {
      final BookingEntity? booking = bookingsById[stop.bookingId];
      final double? lat = stop.isPickup
          ? booking?.resolvedPickupLat
          : booking?.resolvedDropoffLat;
      final double? lng = stop.isPickup
          ? booking?.resolvedPickupLng
          : booking?.resolvedDropoffLng;
      if (lat == null || lng == null) {
        continue;
      }
      final double hue = stop.isCompleted
          ? BitmapDescriptor.hueGreen
          : stop.isSkipped
              ? BitmapDescriptor.hueRose
              : stop.isActive
                  ? BitmapDescriptor.hueBlue
                  : stop.isPickup
                      ? BitmapDescriptor.hueYellow
                      : BitmapDescriptor.hueOrange;
      markers.add(
        Marker(
          markerId: MarkerId('run_stop_${stop.stopId}'),
          position: LatLng(lat, lng),
          zIndexInt: stop.isCurrentWorkItem ? 3 : 1,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: _taskLabel(stop, booking),
            snippet: _stopSubtitle(stop, booking),
          ),
        ),
      );
    }

    return markers;
  }

  LatLngBounds _operationsBounds(DriverRouteOperations? operations) {
    final List<double> lats = <double>[route.originLat, route.destinationLat];
    final List<double> lngs = <double>[route.originLng, route.destinationLng];
    final DriverRouteRunStop? activeStop = operations?.activeStop;
    if (activeStop != null) {
      final BookingEntity? booking = _bookingForStop(operations, activeStop);
      final double? stopLat = activeStop.isPickup
          ? booking?.resolvedPickupLat
          : booking?.resolvedDropoffLat;
      final double? stopLng = activeStop.isPickup
          ? booking?.resolvedPickupLng
          : booking?.resolvedDropoffLng;
      if (stopLat != null && stopLng != null) {
        lats.add(stopLat);
        lngs.add(stopLng);
      }
    }
    if (_myPosition != null) {
      lats.add(_myPosition!.latitude);
      lngs.add(_myPosition!.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(
        lats.reduce((double a, double b) => a < b ? a : b) - 0.01,
        lngs.reduce((double a, double b) => a < b ? a : b) - 0.01,
      ),
      northeast: LatLng(
        lats.reduce((double a, double b) => a > b ? a : b) + 0.01,
        lngs.reduce((double a, double b) => a > b ? a : b) + 0.01,
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel route?'),
        content: const Text(
          'Passengers with existing bookings will be notified.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel route'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await ref.read(cancelRouteProvider.notifier).cancel(route.routeId);
    final CancelRouteState result = ref.read(cancelRouteProvider);
    if (!context.mounted) {
      return;
    }
    if (result.status == CancelRouteStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not cancel route.')),
      );
    } else {
      context.pop();
    }
  }

  Future<void> _startRouteRun(BuildContext context) async {
    final DriverRouteOperations? currentOperations =
        widget.routeOperationsAsync.valueOrNull;
    if (currentOperations != null && currentOperations.bookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No passenger stops yet. Start passenger operations after a booking is confirmed.'),
        ),
      );
      return;
    }
    await ref.read(routeRunActionProvider.notifier).startRun(route.routeId);
    final RouteRunActionState result = ref.read(routeRunActionProvider);
    if (!context.mounted) {
      return;
    }
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not start route run.')),
      );
      return;
    }
    ref.invalidate(driverRouteOperationsProvider(route.routeId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route run started.')),
    );
    final DriverRouteOperations? workspace = result.workspace;
    final DriverRouteRunStop? activeStop = workspace?.activeStop;
    if (activeStop != null && context.mounted) {
      unawaited(context.push('/trip/${activeStop.bookingId}'));
    }
  }

  void _leaveDetails(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  Future<void> _advanceStop(BuildContext context) async {
    await ref.read(routeRunActionProvider.notifier).advanceStop(route.routeId);
    final RouteRunActionState result = ref.read(routeRunActionProvider);
    if (!context.mounted) {
      return;
    }
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not activate stop.')),
      );
      return;
    }
    ref.invalidate(driverRouteOperationsProvider(route.routeId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop activated.')),
    );
  }

  Future<void> _completeStop(BuildContext context) async {
    await ref.read(routeRunActionProvider.notifier).completeStop(route.routeId);
    final RouteRunActionState result = ref.read(routeRunActionProvider);
    if (!context.mounted) {
      return;
    }
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not complete stop.')),
      );
      return;
    }
    ref.invalidate(driverRouteOperationsProvider(route.routeId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop completed.')),
    );
  }

  Future<void> _completeRun(BuildContext context) async {
    await ref.read(routeRunActionProvider.notifier).completeRun(route.routeId);
    final RouteRunActionState result = ref.read(routeRunActionProvider);
    if (!context.mounted) {
      return;
    }
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.error ?? 'Could not complete route run.')),
      );
      return;
    }
    ref.invalidate(driverRouteOperationsProvider(route.routeId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route run completed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = ref.watch(currentUserProvider)?.userId;
    final bool isOwnRoute =
        currentUserId != null && route.driverUserId == currentUserId;
    final DriverRouteOperations? operations =
        isOwnRoute ? widget.routeOperationsAsync.valueOrNull : null;
    final DriverRouteRun? activeRun = operations?.activeRun;
    final RouteRunActionState routeRunActionState =
        ref.watch(routeRunActionProvider);
    final String price =
        'TZS ${NumberFormat('#,###').format(route.pricePerSeatTzs)}';
    final String depTime = DateFormat('EEE d MMM, HH:mm')
        .format(route.departureDatetime.toLocal());

    final bool hasPassengerStops = operations?.bookings.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _leaveDetails(context),
        ),
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 240,
            child: Stack(
              children: <Widget>[
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      (route.originLat + route.destinationLat) / 2,
                      (route.originLng + route.destinationLng) / 2,
                    ),
                    zoom: 8,
                  ),
                  markers: _buildMarkers(),
                  polylines: _buildPolylines(),
                  onMapCreated: (GoogleMapController controller) {
                    Future<void>.delayed(const Duration(milliseconds: 300), () {
                      unawaited(
                        controller.animateCamera(
                          CameraUpdate.newLatLngBounds(
                            _operationsBounds(
                              isOwnRoute
                                  ? widget.routeOperationsAsync.valueOrNull
                                  : null,
                            ),
                            40,
                          ),
                        ),
                      );
                    });
                  },
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                ),
                if (isOwnRoute && operations?.activeStop != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: _RouteMapOverlay(
                      stop: operations!.activeStop!,
                      booking: operations.bookings
                          .where((BookingEntity item) =>
                              item.bookingId ==
                              operations.activeStop!.bookingId)
                          .first,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${route.originName} → ${route.destinationName}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.access_time,
                    label: 'Departure',
                    value: depTime,
                  ),
                  _InfoRow(
                    icon: Icons.event_seat,
                    label: 'Available seats',
                    value: '${route.availableSeats} / ${route.totalSeats}',
                  ),
                  _InfoRow(
                    icon: Icons.payments_outlined,
                    label: 'Price per seat',
                    value: price,
                  ),
                  if (isOwnRoute)
                    _InfoRow(
                      icon: Icons.play_circle_outline,
                      label: 'Route run',
                      value: activeRun == null
                          ? 'Not started'
                          : 'Active • stop ${activeRun.currentStopIndex + 1}',
                    ),
                  _InfoRow(
                    icon: Icons.directions_car,
                    label: 'Vehicle',
                    value: '${route.vehicleModel}  ·  ${route.vehiclePlate}',
                  ),
                  if (route.driverRating != null)
                    _InfoRow(
                      icon: Icons.star,
                      label: 'Driver rating',
                      value:
                          '${route.driverRating!.toStringAsFixed(1)} / 5.0  ·  ${route.driverName}',
                    ),
                  if (!isOwnRoute) ...<Widget>[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/drivers/${route.driverUserId}'),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('View driver profile'),
                    ),
                  ],
                  if (route.waypoints.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Stops',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    ...route.waypoints.map(
                      (RouteWaypoint waypoint) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.circle, size: 8),
                            const SizedBox(width: 8),
                            Text(waypoint.name),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (isOwnRoute) ...<Widget>[
                    const SizedBox(height: 20),
                    _RouteRunSummaryCard(
                      route: route,
                      operations: operations,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Route operations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _RouteOperationsSection(
                      operationsAsync: widget.routeOperationsAsync,
                      actionState: routeRunActionState,
                      onAdvanceStop: () => unawaited(_advanceStop(context)),
                      onCompleteStop: () => unawaited(_completeStop(context)),
                      onCompleteRun: () => unawaited(_completeRun(context)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: isOwnRoute
              ? Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => unawaited(_confirmCancel(context)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Cancel Route'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: activeRun == null
                            ? (hasPassengerStops
                                ? 'Start route run'
                                : 'No rider stops yet')
                            : 'Route run active',
                        loading: routeRunActionState.isLoading &&
                            routeRunActionState.lastAction ==
                                RouteRunActionType.startRun,
                        onPressed: activeRun == null && hasPassengerStops
                            ? () => unawaited(_startRouteRun(context))
                            : null,
                      ),
                    ),
                  ],
                )
              : PrimaryButton(
                  label: 'Book this route — $price',
                  onPressed: route.availableSeats > 0
                      ? () => context.push(
                            '/bookings/create',
                            extra: <String, dynamic>{'routeId': routeId},
                          )
                      : null,
                ),
        ),
      ),
    );
  }

  String get routeId => route.routeId;
}

class _RouteOperationsSection extends StatelessWidget {
  const _RouteOperationsSection({
    required this.operationsAsync,
    required this.actionState,
    required this.onAdvanceStop,
    required this.onCompleteStop,
    required this.onCompleteRun,
  });

  final AsyncValue<DriverRouteOperations> operationsAsync;
  final RouteRunActionState actionState;
  final VoidCallback onAdvanceStop;
  final VoidCallback onCompleteStop;
  final VoidCallback onCompleteRun;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return operationsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text('Could not load route operations: $error'),
      ),
      data: (DriverRouteOperations operations) {
        final List<DriverRouteRunStop> runStops = operations.runStops;
        final Map<String, BookingEntity> bookingsById = <String, BookingEntity>{
          for (final BookingEntity booking in operations.bookings)
            booking.bookingId: booking,
        };
        final DriverRouteRunStop? activeStop = operations.activeStop;

        if (runStops.isEmpty) {
          return Container(
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
                  operations.activeRun == null
                      ? 'No passenger stops yet'
                      : 'No persisted stop plan yet',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  operations.activeRun == null
                      ? 'Your route is posted and visible. Passenger stop management becomes available after a rider books this route.'
                      : 'This run has no stop plan available yet. Refresh after rider tasks are assigned.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (activeStop != null) ...<Widget>[
              _RouteRunActiveTaskCard(
                stop: activeStop,
                booking: bookingsById[activeStop.bookingId],
                actionState: actionState,
                onAdvanceStop: onAdvanceStop,
                onCompleteStop: onCompleteStop,
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Run timeline',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...runStops.map(
              (DriverRouteRunStop stop) => _RouteRunStopTile(
                stop: stop,
                booking: bookingsById[stop.bookingId],
                isCurrentStop: activeStop?.stopId == stop.stopId,
              ),
            ),
            if (operations.activeRun != null &&
                runStops.isNotEmpty &&
                runStops.every((DriverRouteRunStop stop) =>
                    stop.isCompleted || stop.isSkipped)) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Complete route run',
                  loading: actionState.isLoading &&
                      actionState.lastAction == RouteRunActionType.completeRun,
                  onPressed: actionState.isLoading ? null : onCompleteRun,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RouteRunActiveTaskCard extends StatelessWidget {
  const _RouteRunActiveTaskCard({
    required this.stop,
    required this.booking,
    required this.actionState,
    required this.onAdvanceStop,
    required this.onCompleteStop,
  });

  final DriverRouteRunStop stop;
  final BookingEntity? booking;
  final RouteRunActionState actionState;
  final VoidCallback onAdvanceStop;
  final VoidCallback onCompleteStop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int? eta = stop.isPickup
        ? booking?.etaToPickupSeconds
        : booking?.etaToDropoffSeconds;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            scheme.primaryContainer.withOpacity(0.9),
            scheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: scheme.primary.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _StatusChip(
                label: stop.isPickup ? 'Pickup live' : 'Drop-off live',
                color: scheme.primary,
              ),
              const Spacer(),
              if (booking != null)
                Text(
                  booking!.journeyLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _taskLabel(stop, booking),
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _stopSubtitle(stop, booking),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          if (eta != null) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _KpiPill(
                  icon: Icons.schedule,
                  label: 'ETA',
                  value:
                      '${_formatEta(eta)}${booking?.etaApproximate == true ? ' approx.' : ''}',
                ),
                if (booking != null &&
                    (booking!.etaToPickupSeconds != null ||
                        booking!.etaToDropoffSeconds != null))
                  _KpiPill(
                    icon: Icons.person_outline,
                    label: 'Rider',
                    value: booking!.passengerDisplayName,
                  ),
              ],
            ),
          ],
          if (booking != null) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push(
                  booking!.canOpenJourney
                      ? '/trip/${booking!.bookingId}'
                      : '/bookings/${booking!.bookingId}',
                ),
                icon: const Icon(Icons.chevron_right),
                label: Text(
                  booking!.canOpenJourney ? 'Open live trip' : 'Open booking',
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: stop.isActive
                  ? (stop.isPickup ? 'Complete pickup' : 'Complete drop-off')
                  : 'Make current stop live',
              loading: actionState.isLoading &&
                  ((stop.isActive &&
                          actionState.lastAction ==
                              RouteRunActionType.completeStop) ||
                      (!stop.isActive &&
                          actionState.lastAction ==
                              RouteRunActionType.advanceStop)),
              onPressed: actionState.isLoading
                  ? null
                  : (stop.isActive ? onCompleteStop : onAdvanceStop),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRunStopTile extends StatelessWidget {
  const _RouteRunStopTile({
    required this.stop,
    required this.booking,
    required this.isCurrentStop,
  });

  final DriverRouteRunStop stop;
  final BookingEntity? booking;
  final bool isCurrentStop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int? eta = stop.isPickup
        ? booking?.etaToPickupSeconds
        : booking?.etaToDropoffSeconds;
    final Color accentColor = _stopAccentColor(scheme);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: isCurrentStop
            ? scheme.primaryContainer.withOpacity(0.18)
            : scheme.surface,
        border: Border.all(
          color: isCurrentStop ? scheme.primary : scheme.outlineVariant,
          width: isCurrentStop ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${stop.sequence + 1}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _taskLabel(stop, booking),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    _StatusChip(
                      label: _statusLabel(stop),
                      color: accentColor,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _stopSubtitle(stop, booking),
                  style: theme.textTheme.bodySmall,
                ),
                if (eta != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'ETA ${_formatEta(eta)}${booking?.etaApproximate == true ? ' approx.' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (booking != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.push(
                        booking!.canOpenJourney
                            ? '/trip/${booking!.bookingId}'
                            : '/bookings/${booking!.bookingId}',
                      ),
                      child: Text(
                        booking!.canOpenJourney
                            ? 'Open live trip'
                            : 'Open booking',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _stopAccentColor(ColorScheme scheme) {
    if (stop.isCompleted) {
      return Colors.green;
    }
    if (stop.isSkipped) {
      return scheme.error;
    }
    if (isCurrentStop || stop.isActive) {
      return scheme.primary;
    }
    return scheme.outline;
  }
}

class _RouteRunSummaryCard extends StatelessWidget {
  const _RouteRunSummaryCard({
    required this.route,
    required this.operations,
  });

  final RouteEntity route;
  final DriverRouteOperations? operations;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DriverRouteRun? run = operations?.activeRun;
    final DriverRouteRunStop? activeStop = operations?.activeStop;
    final List<DriverRouteRunStop> stops =
        operations?.runStops ?? <DriverRouteRunStop>[];
    final int completedStops = stops
        .where((DriverRouteRunStop stop) => stop.isCompleted || stop.isSkipped)
        .length;
    final int totalStops = stops.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            scheme.secondaryContainer,
            scheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.alt_route, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  run == null
                      ? 'Route ready to launch'
                      : 'Route run in progress',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusChip(
                label: run == null ? 'Not started' : run.status,
                color: run == null ? scheme.outline : scheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            activeStop == null
                ? 'Start the run when you are ready to move toward the first pickup.'
                : '${activeStop.isPickup ? 'Next pickup' : 'Next drop-off'}: ${activeStop.stopName ?? 'Stop ${activeStop.sequence + 1}'}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _KpiPill(
                icon: Icons.timeline,
                label: 'Stops',
                value: totalStops == 0
                    ? 'None yet'
                    : '$completedStops / $totalStops complete',
              ),
              _KpiPill(
                icon: Icons.event_seat,
                label: 'Seats open',
                value: '${route.availableSeats}/${route.totalSeats}',
              ),
              _KpiPill(
                icon: Icons.schedule,
                label: 'Departure',
                value: DateFormat('HH:mm')
                    .format(route.departureDatetime.toLocal()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteMapOverlay extends StatelessWidget {
  const _RouteMapOverlay({
    required this.stop,
    required this.booking,
  });

  final DriverRouteRunStop stop;
  final BookingEntity booking;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int? eta = stop.isPickup
        ? booking.etaToPickupSeconds
        : booking.etaToDropoffSeconds;

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
                stop.isPickup ? Icons.login : Icons.logout,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    stop.isPickup ? 'Current pickup' : 'Current drop-off',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop.stopName ?? _stopSubtitle(stop, booking),
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
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

String _taskLabel(DriverRouteRunStop stop, BookingEntity? booking) {
  final String rider = booking?.passengerDisplayName ?? 'Rider';
  return '${stop.isPickup ? 'Pick up' : 'Drop off'} $rider';
}

String _stopSubtitle(DriverRouteRunStop stop, BookingEntity? booking) {
  final String location = stop.stopName?.trim().isNotEmpty == true
      ? stop.stopName!
      : stop.isPickup
          ? (booking?.pickupDisplayName ?? 'Pickup point')
          : (booking?.dropoffDisplayName ?? 'Drop-off point');
  return '${stop.isPickup ? 'Pickup' : 'Drop-off'} • $location';
}

String _statusLabel(DriverRouteRunStop stop) {
  switch (stop.status) {
    case 'completed':
      return 'Completed';
    case 'skipped':
      return 'Skipped';
    case 'active':
      return 'Current';
    case 'pending':
      return 'Queued';
    default:
      return stop.status.replaceAll('_', ' ');
  }
}

String _formatEta(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  return '${(seconds / 60).ceil()}m';
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
