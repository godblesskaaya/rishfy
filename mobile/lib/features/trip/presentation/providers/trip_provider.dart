import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/config/env.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../bookings/domain/entities/booking_entity.dart';
import '../../data/models/location_models.dart';

// ---- Passenger: subscribe to driver location for a trip ----

class DriverTrackingState {
  const DriverTrackingState({
    this.latest,
    this.history = const <DriverLocationUpdate>[],
    this.isConnected = false,
    this.error,
  });

  final DriverLocationUpdate? latest;
  final List<DriverLocationUpdate> history;
  final bool isConnected;
  final String? error;

  bool get hasLiveContext => latest != null || history.isNotEmpty;

  DriverTrackingState copyWith({
    DriverLocationUpdate? latest,
    List<DriverLocationUpdate>? history,
    bool? isConnected,
    String? error,
  }) =>
      DriverTrackingState(
        latest: latest ?? this.latest,
        history: history ?? this.history,
        isConnected: isConnected ?? this.isConnected,
        error: error,
      );
}

final StateNotifierProviderFamily<DriverTrackingNotifier, DriverTrackingState,
        String> driverTrackingProvider =
    StateNotifierProviderFamily<DriverTrackingNotifier, DriverTrackingState,
        String>(
  (Ref ref, String bookingId) =>
      DriverTrackingNotifier(bookingId, ref.read(secureStorageProvider)),
);

class DriverTrackingNotifier extends StateNotifier<DriverTrackingState> {
  DriverTrackingNotifier(this._bookingId, this._storage)
      : super(const DriverTrackingState());

  final String _bookingId;
  final SecureStorage _storage;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;

  void seedFromBooking(BookingEntity booking) {
    if (booking.driverLat == null || booking.driverLng == null) {
      return;
    }

    final DriverLocationUpdate seeded = DriverLocationUpdate.fromBookingContext(
      driverUserId: booking.driverId ?? '',
      lat: booking.driverLat!,
      lng: booking.driverLng!,
      heading: booking.driverHeading ?? 0,
      speedKmh: booking.driverSpeedKmh ?? 0,
      timestamp: booking.driverLocationUpdatedAt ?? DateTime.now(),
      tripId: booking.tripId,
      bookingId: booking.bookingId,
      journeyState: booking.effectiveJourneyState,
      routeStatus: booking.effectiveRouteStatus,
      stopLabel: booking.isPrePickupJourney
          ? booking.pickupDisplayName
          : booking.dropoffDisplayName,
      stopType: booking.isPrePickupJourney ? 'pickup' : 'dropoff',
      etaToPickupSeconds: booking.etaToPickupSeconds,
      etaToDropoffSeconds: booking.etaToDropoffSeconds,
      etaApproximate: booking.etaApproximate,
      etaStale: booking.etaStale,
    );

    state = state.copyWith(
      latest: seeded,
      history: state.history.isEmpty
          ? <DriverLocationUpdate>[seeded]
          : state.history,
    );
  }

  Future<void> connect(String driverId) async {
    if (state.isConnected) return;

    final String? token = await _storage.readAccessToken();
    final Uri uri = Uri.parse(
      '${Env.wsBaseUrl}/location?booking_id=$_bookingId'
      '${token != null ? '&token=$token' : ''}',
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      state = state.copyWith(isConnected: true, error: null);

      // Tell the server which driver to subscribe to.
      _channel!.sink.add(jsonEncode(<String, dynamic>{
        'type': 'subscribe',
        'driverId': driverId,
      }));

      _sub = _channel!.stream.listen(
        (dynamic raw) {
          try {
            final Map<String, dynamic> json =
                jsonDecode(raw as String) as Map<String, dynamic>;
            if (json['type'] == 'location_update') {
              final DriverLocationUpdate update =
                  DriverLocationUpdate.fromJson(json);
              _recordUpdate(update);
            }
          } catch (_) {}
        },
        onError: (Object e) {
          state = state.copyWith(isConnected: false, error: e.toString());
        },
        onDone: () {
          state = state.copyWith(isConnected: false);
        },
      );
    } catch (e) {
      state = state.copyWith(isConnected: false, error: e.toString());
    }
  }

  void _recordUpdate(DriverLocationUpdate update) {
    final List<DriverLocationUpdate> history = <DriverLocationUpdate>[
      ...state.history,
      update
    ];
    state = state.copyWith(
      latest: update,
      history: history.length > 100
          ? history.sublist(history.length - 100)
          : history,
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_channel?.sink.close());
    super.dispose();
  }
}

// ---- Driver: broadcast own location ----

class DriverBroadcastState {
  const DriverBroadcastState({
    this.isStreaming = false,
    this.lastPosition,
    this.error,
  });

  final bool isStreaming;
  final Position? lastPosition;
  final String? error;
}

final StateNotifierProvider<DriverBroadcastNotifier, DriverBroadcastState>
    driverBroadcastProvider =
    StateNotifierProvider<DriverBroadcastNotifier, DriverBroadcastState>(
  (Ref ref) => DriverBroadcastNotifier(
    ref.read(secureStorageProvider),
    ref.read(currentUserProvider)?.userId ?? '',
  ),
);

class DriverBroadcastNotifier extends StateNotifier<DriverBroadcastState> {
  DriverBroadcastNotifier(this._storage, this._driverUserId)
      : super(const DriverBroadcastState());

  final SecureStorage _storage;
  final String _driverUserId;
  WebSocketChannel? _channel;
  StreamSubscription<Position>? _gpsSub;

  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );

  Future<void> startStreaming(String tripId) async {
    if (state.isStreaming) return;

    final LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      final LocationPermission req = await Geolocator.requestPermission();
      if (req == LocationPermission.denied ||
          req == LocationPermission.deniedForever) {
        state = const DriverBroadcastState(error: 'Location permission denied');
        return;
      }
    }

    final String? token = await _storage.readAccessToken();
    final Uri uri = Uri.parse(
      '${Env.wsBaseUrl}/driver?trip_id=$tripId'
      '${token != null ? '&token=$token' : ''}',
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      state = const DriverBroadcastState(isStreaming: true);

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      ).listen(
        (Position pos) {
          state = DriverBroadcastState(
            isStreaming: true,
            lastPosition: pos,
          );
          _channel?.sink.add(jsonEncode(<String, dynamic>{
            'type': 'location',
            'driverId': _driverUserId,
            'driver_user_id': _driverUserId,
            'trip_id': tripId,
            'lat': pos.latitude,
            'lng': pos.longitude,
            'bearing': pos.heading,
            'speed_kmh': pos.speed * 3.6,
            'timestamp': DateTime.now().toIso8601String(),
          }));
        },
        onError: (Object e) {
          state = DriverBroadcastState(error: e.toString());
        },
      );
    } catch (e) {
      state = DriverBroadcastState(error: e.toString());
    }
  }

  Future<void> stopStreaming() async {
    await _gpsSub?.cancel();
    await _channel?.sink.close();
    _gpsSub = null;
    _channel = null;
    state = const DriverBroadcastState();
  }

  @override
  void dispose() {
    unawaited(_gpsSub?.cancel());
    unawaited(_channel?.sink.close());
    super.dispose();
  }
}
