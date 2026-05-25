import 'package:dio/dio.dart';

import '../models/booking_models.dart';

class BookingRemoteDataSource {
  BookingRemoteDataSource(this._dio);

  final Dio _dio;

  Future<InitiatePaymentResponse> createBooking(
      CreateBookingRequest req) async {
    final Response<Map<String, dynamic>> bookingRes =
        await _dio.post<Map<String, dynamic>>(
      '/api/v1/bookings',
      data: req.toBookingJson(),
    );
    final BookingDto booking =
        BookingDto.fromJson(bookingRes.data as Map<String, dynamic>);

    final Response<Map<String, dynamic>> paymentRes =
        await _dio.post<Map<String, dynamic>>(
      '/api/v1/payments/initiate',
      data: req.toPaymentJson(booking.bookingId),
    );

    return InitiatePaymentResponse.fromJson(<String, dynamic>{
      ...?paymentRes.data,
      'bookingId': booking.bookingId,
    });
  }

  Future<List<BookingDto>> listMyBookings({String role = 'passenger'}) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/bookings/me',
      queryParameters: <String, dynamic>{'role': role},
    );
    final List<dynamic> data =
        res.data?['bookings'] as List<dynamic>? ?? <dynamic>[];
    return data
        .map((dynamic e) => BookingDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BookingDto>> listDriverRouteOperations(String routeId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/bookings/routes/$routeId/operations',
    );
    final List<dynamic> data =
        res.data?['bookings'] as List<dynamic>? ?? <dynamic>[];
    return data
        .map((dynamic e) => BookingDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BookingDto> getBooking(String bookingId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>('/api/v1/bookings/$bookingId');
    return BookingDto.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<String> pollPaymentStatus(String paymentId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>(
      '/api/v1/payments/$paymentId/status',
    );
    return res.data?['status'] as String? ?? 'pending';
  }

  Future<void> cancelBooking(String bookingId, {String? reason}) async {
    await _dio.post<void>(
      '/api/v1/bookings/$bookingId/cancel',
      data: <String, dynamic>{
        'reason': (reason == null || reason.trim().isEmpty)
            ? 'PASSENGER_CANCELLED'
            : reason.trim(),
      },
    );
  }

  Future<void> rateTrip({
    required String bookingId,
    required int rating,
    String? comment,
  }) async {
    await _dio.post<void>(
      '/api/v1/bookings/$bookingId/rate',
      data: <String, dynamic>{
        'rating': rating,
        if (comment != null) 'review': comment,
      },
    );
  }

  Future<void> declineBooking(String bookingId, {String? reason}) async {
    await _dio.post<void>(
      '/api/v1/bookings/$bookingId/decline',
      data: <String, dynamic>{
        'reason': reason ?? 'Driver declined',
      },
    );
  }

  Future<BookingDto> startTrip(String bookingId) async {
    return _postBookingAction(
      '/api/v1/bookings/$bookingId/start-trip',
      data: const <String, dynamic>{},
    );
  }

  Future<BookingDto> completeTrip(String bookingId) async {
    return _postBookingAction(
      '/api/v1/bookings/$bookingId/complete-trip',
      data: const <String, dynamic>{},
    );
  }

  Future<BookingDto> arriveAtPickup(String bookingId) async {
    return _postBookingAction(
      '/api/v1/bookings/$bookingId/arrive-pickup',
      data: const <String, dynamic>{},
    );
  }

  Future<BookingDto> boardPassenger(String bookingId) async {
    try {
      return await _postBookingAction(
        '/api/v1/bookings/$bookingId/board-passenger',
        data: const <String, dynamic>{},
      );
    } on DioException catch (error) {
      if (_shouldFallbackToLegacyAction(error)) {
        return startTrip(bookingId);
      }
      rethrow;
    }
  }

  Future<BookingDto> dropoffPassenger(String bookingId) async {
    try {
      return await _postBookingAction(
        '/api/v1/bookings/$bookingId/dropoff-passenger',
        data: const <String, dynamic>{},
      );
    } on DioException catch (error) {
      if (_shouldFallbackToLegacyAction(error)) {
        return completeTrip(bookingId);
      }
      rethrow;
    }
  }

  Future<BookingDto> markNoShow(String bookingId, {String? reason}) async {
    return _postBookingAction(
      '/api/v1/bookings/$bookingId/mark-no-show',
      data: <String, dynamic>{
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  Future<BookingDto> completeJourney(String bookingId) async {
    return _postBookingAction(
      '/api/v1/bookings/$bookingId/complete-journey',
      data: const <String, dynamic>{},
    );
  }

  Future<BookingDto> _postBookingAction(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final Response<Map<String, dynamic>> res =
        await _dio.post<Map<String, dynamic>>(path, data: data);
    return BookingDto.fromJson(res.data ?? <String, dynamic>{});
  }

  bool _shouldFallbackToLegacyAction(DioException error) {
    final int? statusCode = error.response?.statusCode;
    return statusCode == 404 || statusCode == 405 || statusCode == 501;
  }
}
