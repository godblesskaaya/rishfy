import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/datasources/booking_remote_datasource.dart';
import '../../data/models/booking_models.dart';
import '../../domain/entities/booking_entity.dart';

String _errorMessage(Object e, String fallback) {
  if (e is AppException) return e.message;
  if (e is DioException && e.error is AppException) {
    return (e.error! as AppException).message;
  }
  return fallback;
}

final Provider<BookingRemoteDataSource> bookingDataSourceProvider =
    Provider<BookingRemoteDataSource>(
  (Ref ref) => BookingRemoteDataSource(ref.read(dioClientProvider)),
);

// ---- Create booking ----

enum CreateBookingStatus { idle, loading, awaitingPayment, completed, failed }

class CreateBookingState {
  const CreateBookingState({
    this.status = CreateBookingStatus.idle,
    this.paymentResponse,
    this.paymentStatus,
    this.error,
  });

  final CreateBookingStatus status;
  final InitiatePaymentResponse? paymentResponse;
  final String? paymentStatus;
  final String? error;

  CreateBookingState copyWith({
    CreateBookingStatus? status,
    InitiatePaymentResponse? paymentResponse,
    String? paymentStatus,
    String? error,
  }) =>
      CreateBookingState(
        status: status ?? this.status,
        paymentResponse: paymentResponse ?? this.paymentResponse,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        error: error,
      );
}

final createBookingProvider = StateNotifierProvider.autoDispose<
    CreateBookingNotifier, CreateBookingState>(
  (Ref ref) => CreateBookingNotifier(ref.read(bookingDataSourceProvider)),
);

class CreateBookingNotifier extends StateNotifier<CreateBookingState> {
  CreateBookingNotifier(this._ds) : super(const CreateBookingState());

  final BookingRemoteDataSource _ds;

  Future<void> submit(CreateBookingRequest req) async {
    state = state.copyWith(status: CreateBookingStatus.loading, error: null);
    try {
      final InitiatePaymentResponse resp = await _ds.createBooking(req);
      state = state.copyWith(
        status: CreateBookingStatus.awaitingPayment,
        paymentResponse: resp,
        paymentStatus: resp.status,
      );
    } catch (e) {
      state = state.copyWith(
        status: CreateBookingStatus.failed,
        error:
            _errorMessage(e, 'Could not start the booking. Please try again.'),
      );
    }
  }

  Future<void> pollPaymentStatus() async {
    final String? paymentId = state.paymentResponse?.paymentId;
    if (paymentId == null) return;
    try {
      final String status = await _ds.pollPaymentStatus(paymentId);
      if (status == 'completed' || status == 'confirmed') {
        state = state.copyWith(
          status: CreateBookingStatus.completed,
          paymentStatus: status,
        );
      } else if (status == 'failed') {
        state = state.copyWith(
          status: CreateBookingStatus.failed,
          paymentStatus: status,
          error: 'Payment failed. Please try again.',
        );
      } else {
        state = state.copyWith(paymentStatus: status);
      }
    } catch (_) {}
  }

  void reset() => state = const CreateBookingState();
}

// ---- My bookings list (passenger view) ----

final FutureProvider<List<BookingEntity>> myBookingsProvider =
    FutureProvider<List<BookingEntity>>((Ref ref) async {
  final BookingRemoteDataSource ds = ref.read(bookingDataSourceProvider);
  final List<BookingDto> dtos = await ds.listMyBookings();
  return dtos.map((BookingDto d) => d.toDomain()).toList();
});

// ---- Driver-side bookings (passengers who booked my routes) ----

final FutureProvider<List<BookingEntity>> myDriverBookingsProvider =
    FutureProvider<List<BookingEntity>>((Ref ref) async {
  final BookingRemoteDataSource ds = ref.read(bookingDataSourceProvider);
  final List<BookingDto> dtos = await ds.listMyBookings(role: 'driver');
  return dtos.map((BookingDto d) => d.toDomain()).toList();
});

final Provider<AsyncValue<BookingEntity?>> activePassengerJourneyProvider =
    Provider<AsyncValue<BookingEntity?>>((Ref ref) {
  final AsyncValue<List<BookingEntity>> asyncBookings =
      ref.watch(myBookingsProvider);
  return asyncBookings.whenData(_selectActiveJourney);
});

final Provider<AsyncValue<BookingEntity?>> activeDriverJourneyProvider =
    Provider<AsyncValue<BookingEntity?>>((Ref ref) {
  final AsyncValue<List<BookingEntity>> asyncBookings =
      ref.watch(myDriverBookingsProvider);
  return asyncBookings.whenData(_selectDriverJourney);
});

/// Computed weekly stats for the driver from completed bookings.
class DriverEarningsStats {
  const DriverEarningsStats({
    required this.weekTotalTzs,
    required this.weekTrips,
    required this.lifetimeTrips,
  });

  final int weekTotalTzs;
  final int weekTrips;
  final int lifetimeTrips;
}

final Provider<AsyncValue<DriverEarningsStats>> driverEarningsStatsProvider =
    Provider<AsyncValue<DriverEarningsStats>>((Ref ref) {
  final AsyncValue<List<BookingEntity>> async =
      ref.watch(myDriverBookingsProvider);
  return async.whenData((List<BookingEntity> bookings) {
    final DateTime now = DateTime.now();
    final DateTime weekStart =
        now.subtract(Duration(days: now.weekday - 1)).copyWith(
              hour: 0,
              minute: 0,
              second: 0,
              millisecond: 0,
              microsecond: 0,
            );
    int weekTotal = 0;
    int weekTrips = 0;
    int lifetime = 0;
    for (final BookingEntity b in bookings) {
      if (!b.isCompleted) continue;
      lifetime++;
      final DateTime ts = b.departureDatetime ?? b.createdAt;
      if (ts.isAfter(weekStart)) {
        weekTrips++;
        weekTotal += b.totalPriceTzs;
      }
    }
    return DriverEarningsStats(
      weekTotalTzs: weekTotal,
      weekTrips: weekTrips,
      lifetimeTrips: lifetime,
    );
  });
});

// ---- Single booking detail ----

final FutureProviderFamily<BookingEntity, String> bookingDetailProvider =
    FutureProviderFamily<BookingEntity, String>(
        (Ref ref, String bookingId) async {
  final BookingRemoteDataSource ds = ref.read(bookingDataSourceProvider);
  final BookingDto dto = await ds.getBooking(bookingId);
  return dto.toDomain();
});

// ---- Decline booking (driver only) ----

enum DeclineBookingStatus { idle, loading, success, failed }

class DeclineBookingState {
  const DeclineBookingState({
    this.status = DeclineBookingStatus.idle,
    this.error,
  });

  final DeclineBookingStatus status;
  final String? error;

  DeclineBookingState copyWith({
    DeclineBookingStatus? status,
    String? error,
  }) =>
      DeclineBookingState(
        status: status ?? this.status,
        error: error,
      );
}

final declineBookingProvider = StateNotifierProvider.autoDispose<
    DeclineBookingNotifier, DeclineBookingState>(
  (Ref ref) => DeclineBookingNotifier(ref.read(bookingDataSourceProvider)),
);

class DeclineBookingNotifier extends StateNotifier<DeclineBookingState> {
  DeclineBookingNotifier(this._ds) : super(const DeclineBookingState());

  final BookingRemoteDataSource _ds;

  Future<void> decline(String bookingId, {String? reason}) async {
    state = state.copyWith(status: DeclineBookingStatus.loading, error: null);
    try {
      await _ds.declineBooking(bookingId, reason: reason);
      state = state.copyWith(status: DeclineBookingStatus.success);
    } catch (e) {
      state = state.copyWith(
        status: DeclineBookingStatus.failed,
        error: _errorMessage(e, 'Could not decline the booking.'),
      );
    }
  }

  void reset() => state = const DeclineBookingState();
}

// ---- Trip lifecycle (driver only) ----

enum TripActionStatus { idle, loading, success, failed }

class TripActionState {
  const TripActionState({
    this.status = TripActionStatus.idle,
    this.action,
    this.error,
  });

  final TripActionStatus status;
  final String? action;
  final String? error;

  TripActionState copyWith({
    TripActionStatus? status,
    String? action,
    String? error,
  }) =>
      TripActionState(
        status: status ?? this.status,
        action: action ?? this.action,
        error: error,
      );
}

final journeyActionProvider =
    StateNotifierProvider.autoDispose<JourneyActionNotifier, TripActionState>(
  (Ref ref) => JourneyActionNotifier(ref.read(bookingDataSourceProvider), ref),
);

class JourneyActionNotifier extends StateNotifier<TripActionState> {
  JourneyActionNotifier(this._ds, this._ref) : super(const TripActionState());

  final BookingRemoteDataSource _ds;
  final Ref _ref;

  Future<void> arrivePickup(String bookingId) async {
    await _runAction(
      bookingId: bookingId,
      actionLabel: 'arrive at pickup',
      operation: () => _ds.arriveAtPickup(bookingId),
    );
  }

  Future<void> boardPassenger(String bookingId) async {
    await _runAction(
      bookingId: bookingId,
      actionLabel: 'board passenger',
      operation: () => _ds.boardPassenger(bookingId),
    );
  }

  Future<void> dropoffPassenger(String bookingId) async {
    await _runAction(
      bookingId: bookingId,
      actionLabel: 'drop off passenger',
      operation: () => _ds.dropoffPassenger(bookingId),
    );
  }

  Future<void> markNoShow(String bookingId, {String? reason}) async {
    await _runAction(
      bookingId: bookingId,
      actionLabel: 'mark no-show',
      operation: () => _ds.markNoShow(bookingId, reason: reason),
    );
  }

  Future<void> completeJourney(String bookingId) async {
    await _runAction(
      bookingId: bookingId,
      actionLabel: 'finish journey',
      operation: () => _ds.completeJourney(bookingId),
    );
  }

  Future<void> start(String bookingId) async {
    await _runAction(
      bookingId: bookingId,
      actionLabel: 'start trip',
      operation: () => _ds.startTrip(bookingId),
    );
  }

  Future<void> complete(String bookingId) async {
    await _runAction(
      bookingId: bookingId,
      actionLabel: 'complete trip',
      operation: () => _ds.completeTrip(bookingId),
    );
  }

  Future<void> _runAction({
    required String bookingId,
    required String actionLabel,
    required Future<BookingDto> Function() operation,
  }) async {
    state = state.copyWith(
      status: TripActionStatus.loading,
      action: actionLabel,
      error: null,
    );
    try {
      await operation();
      _invalidateBookingSurfaces(bookingId);
      state = state.copyWith(
        status: TripActionStatus.success,
        action: actionLabel,
      );
    } catch (e) {
      state = state.copyWith(
        status: TripActionStatus.failed,
        action: actionLabel,
        error: _errorMessage(e, 'Could not $actionLabel.'),
      );
    }
  }

  void _invalidateBookingSurfaces(String bookingId) {
    _ref.invalidate(bookingDetailProvider(bookingId));
    _ref.invalidate(myBookingsProvider);
    _ref.invalidate(myDriverBookingsProvider);
    _ref.invalidate(activePassengerJourneyProvider);
    _ref.invalidate(activeDriverJourneyProvider);
    _ref.invalidate(driverEarningsStatsProvider);
  }
}

BookingEntity? _selectActiveJourney(List<BookingEntity> bookings) {
  final List<BookingEntity> active = bookings
      .where((BookingEntity booking) => booking.isJourneyActive)
      .toList()
    ..sort(_sortBookingsForJourneyEntry);
  if (active.isNotEmpty) {
    return active.first;
  }

  final List<BookingEntity> upcoming = bookings
      .where((BookingEntity booking) =>
          !booking.isCancelled &&
          !booking.isNoShow &&
          !booking.isCompleted &&
          !booking.isPending)
      .toList()
    ..sort(_sortBookingsForJourneyEntry);
  if (upcoming.isNotEmpty) {
    return upcoming.first;
  }
  return null;
}

int _sortBookingsForJourneyEntry(BookingEntity a, BookingEntity b) {
  final int aEta = a.etaToPickupSeconds ?? a.etaToDropoffSeconds ?? (1 << 30);
  final int bEta = b.etaToPickupSeconds ?? b.etaToDropoffSeconds ?? (1 << 30);
  if (aEta != bEta) {
    return aEta.compareTo(bEta);
  }
  final DateTime aTime = a.departureDatetime ?? a.createdAt;
  final DateTime bTime = b.departureDatetime ?? b.createdAt;
  return aTime.compareTo(bTime);
}

BookingEntity? _selectDriverJourney(List<BookingEntity> bookings) {
  final List<BookingEntity> operational = bookings
      .where((BookingEntity booking) =>
          !booking.isCancelled &&
          !booking.isNoShow &&
          !booking.isCompleted &&
          (booking.canDriverMarkArrived ||
              booking.canDriverMarkBoarded ||
              booking.canDriverMarkDroppedOff))
      .toList()
    ..sort(_sortBookingsForJourneyEntry);
  if (operational.isNotEmpty) {
    return operational.first;
  }

  final List<BookingEntity> upcoming = bookings
      .where((BookingEntity booking) =>
          !booking.isCancelled &&
          !booking.isNoShow &&
          !booking.isCompleted &&
          !booking.isPostDropoffJourney)
      .toList()
    ..sort(_sortBookingsForJourneyEntry);
  if (upcoming.isNotEmpty) {
    return upcoming.first;
  }

  return null;
}
