import { BookingRepository } from '../repositories/booking.repository.js';
import { reserveSeats, releaseSeats } from '../clients/route.grpc.client.js';
import { config } from '../config.js';
import { logger } from '../logger.js';
import {
  publishBookingCreated, publishBookingConfirmed, publishBookingCancelled,
  publishBookingCompleted, publishBookingExpired, publishTripStarted,
  publishTripCompleted, publishBookingRated,
} from '../events/booking.events.js';
import type { BookingRow } from '../repositories/booking.repository.js';

export interface CreateBookingParams {
  routeId: string;
  passengerId: string;
  driverId: string;
  seatsBooked: number;
  pricePerSeat: number;
  pickupName?: string;
  dropoffName?: string;
  pickupLat?: number;
  pickupLng?: number;
  dropoffLat?: number;
  dropoffLng?: number;
  idempotencyKey: string;
}

export class BookingService {
  constructor(private readonly repo: BookingRepository) {}

  async createBooking(params: CreateBookingParams): Promise<BookingRow> {
    const totalPrice = params.pricePerSeat * params.seatsBooked;
    const platformFee = Math.round(totalPrice * config.PLATFORM_FEE_PERCENT / 100);
    const driverEarnings = totalPrice - platformFee;
    const expiresAt = new Date(Date.now() + config.BOOKING_EXPIRY_SECONDS * 1000);

    // Step 1: Reserve seats (distributed lock via row-level lock in route-service)
    const reservation = await reserveSeats(params.routeId, params.seatsBooked, params.idempotencyKey);
    if (!reservation.success) {
      const err = new Error(`Cannot reserve seats: ${reservation.failureReason}`);
      (err as NodeJS.ErrnoException).code = reservation.failureReason;
      throw err;
    }

    // Step 2: Persist booking record
    let booking: BookingRow;
    try {
      booking = await this.repo.create({
        routeId: params.routeId,
        passengerId: params.passengerId,
        driverId: params.driverId,
        seatsBooked: params.seatsBooked,
        pickupName: params.pickupName,
        dropoffName: params.dropoffName,
        pickupLat: params.pickupLat,
        pickupLng: params.pickupLng,
        dropoffLat: params.dropoffLat,
        dropoffLng: params.dropoffLng,
        totalPrice,
        platformFee,
        driverEarnings,
        idempotencyKey: params.idempotencyKey,
        expiresAt,
      });
    } catch (err) {
      // Rollback seat reservation on DB failure
      await releaseSeats(params.idempotencyKey, 'BOOKING_DB_ERROR');
      throw err;
    }

    await this.repo.appendEvent(booking.id, 'booking.created', { params });

    await publishBookingCreated({
      bookingId: booking.id,
      routeId: booking.route_id,
      passengerId: booking.passenger_id,
      driverId: booking.driver_id,
      seatsBooked: booking.seats_booked,
      totalPrice,
      confirmationCode: booking.confirmation_code ?? '',
      timestamp: new Date().toISOString(),
    });

    return booking;
  }

  async confirmBooking(bookingId: string, paymentId: string): Promise<BookingRow> {
    const booking = await this.repo.confirm(bookingId, paymentId);
    await this.repo.appendEvent(bookingId, 'booking.confirmed', { paymentId });
    await publishBookingConfirmed({
      bookingId: booking.id,
      routeId: booking.route_id,
      passengerId: booking.passenger_id,
      driverId: booking.driver_id,
      paymentId,
      confirmationCode: booking.confirmation_code ?? '',
      timestamp: new Date().toISOString(),
    });
    return booking;
  }

  async cancelByPassenger(bookingId: string, passengerId: string, reason: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    if (booking.passenger_id !== passengerId) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });

    const updated = await this.repo.cancelByPassenger(bookingId, reason);
    if (!updated) throw Object.assign(new Error('Cannot cancel booking in current state'), { code: 'INVALID_STATE' });

    await releaseSeats(bookingId, 'PASSENGER_CANCELLED');
    await this.repo.appendEvent(bookingId, 'booking.cancelled', { reason, cancelledBy: 'passenger' });
    await publishBookingCancelled({
      bookingId, routeId: updated.route_id, passengerId: updated.passenger_id,
      driverId: updated.driver_id, cancelledBy: 'passenger', reason,
      timestamp: new Date().toISOString(),
    });
    return updated;
  }

  async handleDriverCancelledRoute(routeId: string): Promise<void> {
    const bookings = await this.repo.cancelByDriver(routeId);
    await Promise.all(bookings.map(async (b) => {
      await releaseSeats(b.id, 'DRIVER_CANCELLED_ROUTE');
      await this.repo.appendEvent(b.id, 'booking.cancelled', { reason: 'DRIVER_CANCELLED_ROUTE', cancelledBy: 'driver' });
      await publishBookingCancelled({
        bookingId: b.id, routeId, passengerId: b.passenger_id, driverId: b.driver_id,
        cancelledBy: 'driver', reason: 'DRIVER_CANCELLED_ROUTE', timestamp: new Date().toISOString(),
      });
    }));
  }

  async expireBooking(bookingId: string): Promise<void> {
    const booking = await this.repo.findById(bookingId);
    if (!booking || booking.status !== 'pending') return;
    await this.repo.markExpired(bookingId);
    await releaseSeats(bookingId, 'EXPIRED');
    await this.repo.appendEvent(bookingId, 'booking.expired', {});
    await publishBookingExpired({
      bookingId, routeId: booking.route_id, passengerId: booking.passenger_id,
      seatsBooked: booking.seats_booked, timestamp: new Date().toISOString(),
    });
  }

  async startTrip(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    if (booking.driver_id !== driverId) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });
    const updated = await this.repo.startTrip(bookingId);
    if (!updated) throw Object.assign(new Error('Cannot start trip in current state'), { code: 'INVALID_STATE' });
    await this.repo.appendEvent(bookingId, 'trip.started', { driverId });
    await publishTripStarted({ bookingId, driverId, passengerId: updated.passenger_id, timestamp: new Date().toISOString() });
    return updated;
  }

  async completeTrip(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    if (booking.driver_id !== driverId) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });
    const updated = await this.repo.completeTrip(bookingId);
    if (!updated) throw Object.assign(new Error('Cannot complete trip in current state'), { code: 'INVALID_STATE' });
    await this.repo.appendEvent(bookingId, 'trip.completed', { driverId });
    await publishTripCompleted({
      bookingId, driverId, passengerId: updated.passenger_id,
      driverEarnings: parseFloat(updated.driver_earnings),
      timestamp: new Date().toISOString(),
    });
    await publishBookingCompleted({
      bookingId, routeId: updated.route_id, passengerId: updated.passenger_id, driverId,
      totalPrice: parseFloat(updated.total_price), driverEarnings: parseFloat(updated.driver_earnings),
      timestamp: new Date().toISOString(),
    });
    return updated;
  }

  async submitRating(bookingId: string, raterId: string, rating: number, review: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    const isPassenger = booking.passenger_id === raterId;
    const isDriver = booking.driver_id === raterId;
    if (!isPassenger && !isDriver) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });
    const updated = await this.repo.submitRating(bookingId, isPassenger, rating, review);
    if (!updated) throw Object.assign(new Error('Cannot rate booking in current state'), { code: 'INVALID_STATE' });
    await this.repo.appendEvent(bookingId, 'booking.rated', { raterId, rating, review });
    const ratedId = isPassenger ? booking.driver_id : booking.passenger_id;
    await publishBookingRated({
      bookingId, raterId, ratedId, rating, raterRole: isPassenger ? 'passenger' : 'driver',
      timestamp: new Date().toISOString(),
    });
    return updated;
  }

  async getBooking(id: string): Promise<BookingRow | null> {
    return this.repo.findById(id);
  }

  async getByCode(code: string): Promise<BookingRow | null> {
    return this.repo.findByCode(code);
  }

  async listMyBookings(userId: string, role: 'passenger' | 'driver', limit = 20, offset = 0): Promise<BookingRow[]> {
    if (role === 'driver') return this.repo.listByDriver(userId, limit, offset);
    return this.repo.listByPassenger(userId, limit, offset);
  }

  async handlePaymentCompleted(bookingId: string, paymentId: string): Promise<void> {
    const booking = await this.repo.findById(bookingId);
    if (!booking || booking.status !== 'pending') return;
    await this.confirmBooking(bookingId, paymentId);
    logger.info({ bookingId, paymentId }, 'Booking confirmed via payment.completed event');
  }

  async handlePaymentFailed(bookingId: string): Promise<void> {
    const booking = await this.repo.findById(bookingId);
    if (!booking || booking.status !== 'pending') return;
    await this.repo.cancelByPassenger(bookingId, 'PAYMENT_FAILED');
    await releaseSeats(bookingId, 'PAYMENT_FAILED');
    logger.info({ bookingId }, 'Booking cancelled via payment.failed event');
  }
}
