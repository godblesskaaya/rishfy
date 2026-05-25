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
    if (route.encodedPolyline == null || route.encodedPolyline!.isEmpty) {
      return <Polyline>{};
    }
    final List<List<num>> coords = decodePolyline(route.encodedPolyline!);
    final List<LatLng> points = coords
        .map((List<num> point) => LatLng(point[0].toDouble(), point[1].toDouble()))
        .toList();
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: Colors.blue,
        width: 4,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    return <Marker>{
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };
  }

  LatLngBounds _bounds() {
    final List<double> lats = <double>[route.originLat, route.destinationLat];
    final List<double> lngs = <double>[route.originLng, route.destinationLng];
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
    await ref.read(startRouteRunProvider.notifier).start(route.routeId);
    final StartRouteRunState result = ref.read(startRouteRunProvider);
    if (!context.mounted) {
      return;
    }
    if (result.status == StartRouteRunStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not start route run.')),
      );
      return;
    }
    ref.invalidate(driverRouteOperationsProvider(route.routeId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route run started.')),
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
    final StartRouteRunState startRunState = ref.watch(startRouteRunProvider);
    final String price =
        'TZS ${NumberFormat('#,###').format(route.pricePerSeatTzs)}';
    final String depTime =
        DateFormat('EEE d MMM, HH:mm').format(route.departureDatetime.toLocal());

    return Scaffold(
      appBar: AppBar(title: const Text('Route details')),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 240,
            child: GoogleMap(
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
                  controller.animateCamera(
                    CameraUpdate.newLatLngBounds(_bounds(), 40),
                  );
                });
              },
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
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
                    Text(
                      'Route operations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _RouteOperationsSection(
                      operationsAsync: widget.routeOperationsAsync,
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
                            ? 'Start route run'
                            : 'Route run active',
                        loading:
                            startRunState.status == StartRouteRunStatus.loading,
                        onPressed: activeRun == null
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
  });

  final AsyncValue<DriverRouteOperations> operationsAsync;

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
                      ? 'Route run not started'
                      : 'No persisted stop plan yet',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  operations.activeRun == null
                      ? 'Start the route run when you are ready to drive. The server-managed stop list becomes the driver timeline.'
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
  });

  final DriverRouteRunStop stop;
  final BookingEntity? booking;

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
        color: scheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Current route task',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _taskLabel(stop, booking),
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onPrimaryContainer,
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
            Text(
              'ETA ${_formatEta(eta)}${booking?.etaApproximate == true ? ' approx.' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
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
