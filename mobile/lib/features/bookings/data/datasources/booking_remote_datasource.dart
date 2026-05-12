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

  Future<BookingDto> getBooking(String bookingId) async {
    final Response<Map<String, dynamic>> res =
        await _dio.get<Map<String, dynamic>>('/api/v1/bookings/$bookingId');
    return BookingDto.fromJson(
        res.data?['booking'] as Map<String, dynamic>? ?? res.data!);
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
}
