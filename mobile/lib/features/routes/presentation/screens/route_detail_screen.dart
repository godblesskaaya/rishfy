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
import '../../domain/entities/route_entity.dart';
import '../providers/route_provider.dart';

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({required this.routeId, super.key});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RouteEntity> asyncRoute =
        ref.watch(routeDetailProvider(routeId));

    return asyncRoute.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, _) => Scaffold(
        appBar: AppBar(title: const Text('Route details')),
        body: Center(child: Text('Failed to load route: $e')),
      ),
      data: (RouteEntity route) => _RouteDetailBody(route: route),
    );
  }
}

class _RouteDetailBody extends ConsumerStatefulWidget {
  const _RouteDetailBody({required this.route});

  final RouteEntity route;

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
          perm == LocationPermission.deniedForever) return;
      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      if (mounted) setState(() => _myPosition = pos);
    } catch (_) {
      // Location unavailable — no marker shown
    }
  }

  Set<Polyline> _buildPolylines() {
    if (route.encodedPolyline == null || route.encodedPolyline!.isEmpty) {
      return <Polyline>{};
    }
    final List<List<num>> coords =
        decodePolyline(route.encodedPolyline!);
    final List<LatLng> points = coords
        .map((List<num> p) => LatLng(p[0].toDouble(), p[1].toDouble()))
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
        (RouteWaypoint wp) => Marker(
          markerId: MarkerId('wp_${wp.order}'),
          position: LatLng(wp.lat, wp.lng),
          infoWindow: InfoWindow(title: wp.name),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
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
    if (confirmed != true) return;
    if (!context.mounted) return;
    await ref.read(cancelRouteProvider.notifier).cancel(route.routeId);
    final CancelRouteState result = ref.read(cancelRouteProvider);
    if (!context.mounted) return;
    if (result.status == CancelRouteStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not cancel route.')),
      );
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = ref.watch(currentUserProvider)?.userId;
    final bool isOwnRoute = currentUserId != null && route.driverUserId == currentUserId;
    final String price =
        'TZS ${NumberFormat('#,###').format(route.pricePerSeatTzs)}';
    final String depTime =
        DateFormat('EEE d MMM, HH:mm').format(route.departureDatetime.toLocal());

    return Scaffold(
      appBar: AppBar(title: const Text('Route details')),
      body: Column(
        children: <Widget>[
          // Map preview
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

          // Route info
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
                      icon: Icons.access_time, label: 'Departure', value: depTime),
                  _InfoRow(
                      icon: Icons.event_seat,
                      label: 'Available seats',
                      value: '${route.availableSeats} / ${route.totalSeats}'),
                  _InfoRow(
                      icon: Icons.payments_outlined,
                      label: 'Price per seat',
                      value: price),
                  _InfoRow(
                      icon: Icons.directions_car,
                      label: 'Vehicle',
                      value:
                          '${route.vehicleModel}  ·  ${route.vehiclePlate}'),
                  if (route.driverRating != null)
                    _InfoRow(
                        icon: Icons.star,
                        label: 'Driver rating',
                        value:
                            '${route.driverRating!.toStringAsFixed(1)} / 5.0  ·  ${route.driverName}'),
                  if (route.waypoints.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text('Stops',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    ...route.waypoints.map(
                      (RouteWaypoint wp) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.circle, size: 8),
                            const SizedBox(width: 8),
                            Text(wp.name),
                          ],
                        ),
                      ),
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
              ? OutlinedButton(
                  onPressed: () => unawaited(_confirmCancel(context)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Cancel Route'),
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

  // ignore: unused_element — used above
  String get routeId => route.routeId;
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
                Text(label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        )),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
