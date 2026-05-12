import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/datasources/booking_remote_datasource.dart';
import '../../data/models/booking_models.dart';
import '../../domain/entities/booking_entity.dart';

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

final createBookingProvider =
    StateNotifierProvider.autoDispose<CreateBookingNotifier,
        CreateBookingState>(
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
        error: e.toString(),
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

// ---- My bookings list ----

final FutureProvider<List<BookingEntity>> myBookingsProvider =
    FutureProvider<List<BookingEntity>>((Ref ref) async {
  final BookingRemoteDataSource ds = ref.read(bookingDataSourceProvider);
  final List<BookingDto> dtos = await ds.listMyBookings();
  return dtos.map((BookingDto d) => d.toDomain()).toList();
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

final declineBookingProvider =
    StateNotifierProvider.autoDispose<DeclineBookingNotifier,
        DeclineBookingState>(
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
        error: e.toString(),
      );
    }
  }

  void reset() => state = const DeclineBookingState();
}
