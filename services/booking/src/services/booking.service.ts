import { BookingRepository } from '../repositories/booking.repository.js';
import { reserveSeats, releaseSeats } from '../clients/route.grpc.client.js';
import { refundPayment } from '../clients/payment.grpc.client.js';
import {
  completeTrackedTrip,
  startTrackedTrip,
} from '../clients/location.grpc.client.js';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { v4 as uuidv4 } from 'uuid';
import {
  publishBookingCreated, publishBookingConfirmed, publishBookingCancelled,
  publishBookingCompleted, publishBookingExpired, publishTripStarted,
  publishTripCompleted, publishBookingRated, publishBookingEmergency,
  publishBookingDeclined, publishBookingJourneyStarted,
  publishDriverArrivedPickup, publishPassengerBoarded, publishPassengerDroppedOff,
  publishPassengerWalkingToDestination, publishBookingJourneyCompleted,
  publishBookingNoShow,
} from '../events/booking.events.js';
import type { BookingRow } from '../repositories/booking.repository.js';

type ActionJourneyState = BookingRow['journey_state'];

const LEGACY_BOARDED_STATE: ActionJourneyState = 'boarded';
const NORMALIZED_IN_TRANSIT_STATE: ActionJourneyState = 'in_transit';
const PASSENGER_CANCELLABLE_STATES: readonly ActionJourneyState[] = [null, 'confirmed', 'driver_approaching', 'driver_arrived'];
const ARRIVE_PICKUP_STATES: readonly ActionJourneyState[] = [null, 'confirmed', 'driver_approaching'];
const BOARD_PASSENGER_STATES: readonly ActionJourneyState[] = ['driver_arrived'];
const NO_SHOW_STATES: readonly ActionJourneyState[] = ['driver_arrived'];
const IN_VEHICLE_STATES: readonly ActionJourneyState[] = [LEGACY_BOARDED_STATE, NORMALIZED_IN_TRANSIT_STATE];
const JOURNEY_COMPLETION_STATES: readonly ActionJourneyState[] = ['walking_to_destination', 'dropped_off'];

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
  // Matching-derived fields from search results
  pickupWalkingDistance?: number;
  dropoffWalkingDistance?: number;
  pickupWalkingTime?: number;
  estimatedPickupTime?: Date;
  suggestedPickupName?: string;
  pickupPointLat?: number;
  pickupPointLng?: number;
  dropoffPointLat?: number;
  dropoffPointLng?: number;
  idempotencyKey: string;
}

export interface CancelBookingResult {
  booking: BookingRow;
  refund: {
    attempted: boolean;
    applied: boolean;
    refundedAmountTzs: number;
    refundReference: string;
  };
}

export class BookingService {
  constructor(private readonly repo: BookingRepository) {}

  private normalizeJourneyState(journeyState: ActionJourneyState): ActionJourneyState {
    return journeyState === LEGACY_BOARDED_STATE ? NORMALIZED_IN_TRANSIT_STATE : journeyState;
  }

  private normalizeBooking<T extends BookingRow | null>(booking: T): T {
    if (!booking || booking.journey_state !== LEGACY_BOARDED_STATE) {
      return booking;
    }

    return {
      ...booking,
      journey_state: this.normalizeJourneyState(booking.journey_state),
    };
  }

  private ensureJourneyState(
    booking: BookingRow,
    allowedStates: readonly ActionJourneyState[],
    errorMessage: string,
  ): void {
    if (allowedStates.includes(this.normalizeJourneyState(booking.journey_state))) return;
    throw Object.assign(new Error(errorMessage), { code: 'INVALID_STATE' });
  }

  private async getBookingForDriverAction(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    if (booking.driver_id !== driverId) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });
    return this.normalizeBooking(booking)!;
  }

  private async getBookingForParticipantAction(bookingId: string, actorId: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    if (booking.driver_id !== actorId && booking.passenger_id !== actorId) {
      throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });
    }
    return this.normalizeBooking(booking)!;
  }

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
        pickupWalkingDistance: params.pickupWalkingDistance,
        dropoffWalkingDistance: params.dropoffWalkingDistance,
        pickupWalkingTime: params.pickupWalkingTime,
        estimatedPickupTime: params.estimatedPickupTime,
        suggestedPickupName: params.suggestedPickupName,
        pickupPointLat: params.pickupPointLat,
        pickupPointLng: params.pickupPointLng,
        dropoffPointLat: params.dropoffPointLat,
        dropoffPointLng: params.dropoffPointLng,
        totalPrice,
        platformFee,
        driverEarnings,
        idempotencyKey: params.idempotencyKey,
        expiresAt,
      });
    } catch (err) {
      // Rollback seat reservation on DB failure
      await releaseSeats(params.routeId, params.idempotencyKey, 'BOOKING_DB_ERROR');
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
      suggestedPickupName: params.suggestedPickupName,
      suggestedPickupLat: params.pickupPointLat,
      suggestedPickupLng: params.pickupPointLng,
      estimatedPickupTime: params.estimatedPickupTime?.toISOString(),
    });

    return this.normalizeBooking(booking)!;
  }

  async confirmBooking(bookingId: string, paymentId: string): Promise<BookingRow> {
    const booking = await this.repo.confirm(bookingId, paymentId);
    await this.repo.appendEvent(bookingId, 'booking.confirmed', { paymentId });
    await this.repo.appendEvent(bookingId, 'booking.journey_started', { paymentId, journeyState: booking.journey_state });
    await publishBookingConfirmed({
      bookingId: booking.id,
      routeId: booking.route_id,
      passengerId: booking.passenger_id,
      driverId: booking.driver_id,
      paymentId,
      confirmationCode: booking.confirmation_code ?? '',
      timestamp: new Date().toISOString(),
    });
    await publishBookingJourneyStarted({
      bookingId: booking.id,
      routeId: booking.route_id,
      passengerId: booking.passenger_id,
      driverId: booking.driver_id,
      tripId: booking.trip_id ?? '',
      pickupName: booking.suggested_pickup_name ?? booking.pickup_name ?? '',
      dropoffName: booking.dropoff_name ?? '',
      timestamp: new Date().toISOString(),
    });
    return this.normalizeBooking(booking)!;
  }

  async cancelByPassengerWithRefund(bookingId: string, passengerId: string, reason: string): Promise<CancelBookingResult> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    if (booking.passenger_id !== passengerId) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });
    this.ensureJourneyState(booking, PASSENGER_CANCELLABLE_STATES, 'Cannot cancel booking in current state');

    const updated = await this.repo.cancelByPassenger(bookingId, reason);
    if (!updated) throw Object.assign(new Error('Cannot cancel booking in current state'), { code: 'INVALID_STATE' });

    await releaseSeats(updated.route_id, bookingId, 'PASSENGER_CANCELLED');
    await this.repo.appendEvent(bookingId, 'booking.cancelled', { reason, cancelledBy: 'passenger' });
    await publishBookingCancelled({
      bookingId, routeId: updated.route_id, passengerId: updated.passenger_id,
      driverId: updated.driver_id, cancelledBy: 'passenger', reason,
      timestamp: new Date().toISOString(),
    });

    const refund = {
      attempted: false,
      applied: false,
      refundedAmountTzs: 0,
      refundReference: '',
    };

    if (updated.payment_id && updated.payment_status === 'paid') {
      refund.attempted = true;
      const refundResult = await refundPayment(updated.payment_id, passengerId, reason);
      if (refundResult && refundResult.refundedAmountTzs > 0) {
        refund.applied = true;
        refund.refundedAmountTzs = refundResult.refundedAmountTzs;
        refund.refundReference = refundResult.refundReference;
        await this.repo.markPaymentRefunded(bookingId, 'PAYMENT_SERVICE_POLICY');
        await this.repo.appendEvent(bookingId, 'booking.refund_applied', {
          paymentId: updated.payment_id,
          refundedAmountTzs: refundResult.refundedAmountTzs,
          refundReference: refundResult.refundReference,
        });
      } else {
        await this.repo.appendEvent(bookingId, 'booking.refund_pending', {
          paymentId: updated.payment_id,
          reason: 'PAYMENT_REFUND_UNAVAILABLE',
        });
      }
    }

    return { booking: this.normalizeBooking(updated)!, refund };
  }

  async cancelByPassenger(bookingId: string, passengerId: string, reason: string): Promise<BookingRow> {
    const result = await this.cancelByPassengerWithRefund(bookingId, passengerId, reason);
    return result.booking;
  }

  async declineBooking(bookingId: string, driverId: string, reason: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });
    if (booking.driver_id !== driverId) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });

    const updated = await this.repo.decline(bookingId, driverId, reason);
    if (!updated) throw Object.assign(new Error('Cannot decline: booking is not pending or decline window has expired'), { code: 'CANNOT_DECLINE' });

    await releaseSeats(updated.route_id, bookingId, 'DRIVER_DECLINED');
    await this.repo.appendEvent(bookingId, 'booking.declined', { reason, declinedBy: driverId });
    await publishBookingDeclined({
      bookingId, routeId: updated.route_id,
      passengerId: updated.passenger_id, driverId,
      reason, timestamp: new Date().toISOString(),
    });

    return this.normalizeBooking(updated)!;
  }

  async handleDriverCancelledRoute(routeId: string): Promise<void> {
    const bookings = await this.repo.cancelByDriver(routeId);
    await Promise.all(bookings.map(async (b) => {
      await releaseSeats(routeId, b.id, 'DRIVER_CANCELLED_ROUTE');
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
    await releaseSeats(booking.route_id, bookingId, 'EXPIRED');
    await this.repo.appendEvent(bookingId, 'booking.expired', {});
    await publishBookingExpired({
      bookingId, routeId: booking.route_id, passengerId: booking.passenger_id,
      seatsBooked: booking.seats_booked, timestamp: new Date().toISOString(),
    });
  }

  async startTrip(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.getBookingForDriverAction(bookingId, driverId);
    this.ensureJourneyState(booking, [null, 'confirmed'], 'Cannot start trip in current state');

    const updated = await this.repo.startTrip(bookingId);
    if (!updated) {
      throw Object.assign(new Error('Cannot start trip in current state'), { code: 'INVALID_STATE' });
    }

    await this.repo.appendEvent(bookingId, 'booking.trip_started', {
      driverId,
      passengerId: updated.passenger_id,
      tripId: updated.trip_id ?? '',
      timestamp: new Date().toISOString(),
      journeyState: updated.journey_state,
    });
    await publishTripStarted({
      bookingId,
      driverId,
      passengerId: updated.passenger_id,
      timestamp: new Date().toISOString(),
    });

    return this.normalizeBooking(updated)!;
  }

  async completeTrip(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.getBookingForDriverAction(bookingId, driverId);
    const journeyState = this.normalizeJourneyState(booking.journey_state);

    // Preserve the legacy endpoint while keeping lifecycle progression coherent:
    // active transport advances to dropoff, and only the post-dropoff states can close the journey.
    if (IN_VEHICLE_STATES.includes(journeyState)) {
      return this.dropoffPassenger(bookingId, driverId);
    }
    if (JOURNEY_COMPLETION_STATES.includes(journeyState)) {
      return this.completeJourney(bookingId, driverId);
    }

    throw Object.assign(new Error('Cannot complete trip in current state'), { code: 'INVALID_STATE' });
  }

  async arrivePickup(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.getBookingForDriverAction(bookingId, driverId);
    this.ensureJourneyState(booking, ARRIVE_PICKUP_STATES, 'Cannot mark arrival in current state');
    const updated = await this.repo.markDriverArrived(bookingId);
    if (!updated) throw Object.assign(new Error('Cannot mark arrival in current state'), { code: 'INVALID_STATE' });

    const timestamp = new Date().toISOString();
    await this.repo.appendEvent(bookingId, 'driver.arrived_pickup', { driverId, tripId: updated.trip_id ?? '', timestamp });
    await publishDriverArrivedPickup({
      bookingId,
      routeId: updated.route_id,
      passengerId: updated.passenger_id,
      driverId,
      tripId: updated.trip_id ?? '',
      timestamp,
    });
    return this.normalizeBooking(updated)!;
  }

  async boardPassenger(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.getBookingForDriverAction(bookingId, driverId);
    this.ensureJourneyState(booking, BOARD_PASSENGER_STATES, 'Cannot board passenger in current state');
    const tripId = booking.trip_id
      ?? await startTrackedTrip({
        bookingId,
        routeId: booking.route_id,
        driverUserId: driverId,
        startLat: booking.pickup_lat ?? booking.dropoff_lat ?? 0,
        startLng: booking.pickup_lng ?? booking.dropoff_lng ?? 0,
        destinationLat: booking.dropoff_lat ?? booking.pickup_lat ?? 0,
        destinationLng: booking.dropoff_lng ?? booking.pickup_lng ?? 0,
      })
      ?? uuidv4();
    const updated = await this.repo.boardPassenger(bookingId, tripId);
    if (!updated) throw Object.assign(new Error('Cannot board passenger in current state'), { code: 'INVALID_STATE' });

    const timestamp = new Date().toISOString();
    await this.repo.appendEvent(bookingId, 'passenger.boarded', { driverId, tripId, timestamp });
    await this.repo.appendEvent(bookingId, 'trip.started', { driverId, tripId, timestamp });
    await publishPassengerBoarded({
      bookingId,
      routeId: updated.route_id,
      passengerId: updated.passenger_id,
      driverId,
      tripId,
      timestamp,
    });
    await publishTripStarted({ bookingId, driverId, passengerId: updated.passenger_id, timestamp });
    return this.normalizeBooking(updated)!;
  }

  async dropoffPassenger(bookingId: string, driverId: string): Promise<BookingRow> {
    const booking = await this.getBookingForDriverAction(bookingId, driverId);
    this.ensureJourneyState(booking, IN_VEHICLE_STATES, 'Cannot drop off passenger in current state');
    const updated = await this.repo.dropoffPassenger(bookingId);
    if (!updated) throw Object.assign(new Error('Cannot drop off passenger in current state'), { code: 'INVALID_STATE' });

    const tripId = updated.trip_id ?? booking.trip_id ?? '';
    const timestamp = new Date().toISOString();
    await this.repo.appendEvent(bookingId, 'passenger.dropped_off', { driverId, tripId, timestamp });
    await this.repo.appendEvent(bookingId, 'passenger.walking_to_destination', { driverId, tripId, timestamp });
    await this.repo.appendEvent(bookingId, 'trip.completed', { driverId, tripId, timestamp });
    await publishPassengerDroppedOff({
      bookingId,
      routeId: updated.route_id,
      passengerId: updated.passenger_id,
      driverId,
      tripId,
      timestamp,
    });
    await publishPassengerWalkingToDestination({
      bookingId,
      routeId: updated.route_id,
      passengerId: updated.passenger_id,
      driverId,
      tripId,
      timestamp,
    });
    await publishTripCompleted({
      bookingId, driverId, passengerId: updated.passenger_id,
      driverEarnings: parseFloat(updated.driver_earnings),
      timestamp,
    });
    if (tripId) {
      await completeTrackedTrip({
        tripId,
        endLat: updated.dropoff_lat ?? updated.pickup_lat ?? 0,
        endLng: updated.dropoff_lng ?? updated.pickup_lng ?? 0,
      });
    }
    return this.normalizeBooking(updated)!;
  }

  async markNoShow(bookingId: string, driverId: string, reason: string): Promise<BookingRow> {
    const booking = await this.getBookingForDriverAction(bookingId, driverId);
    this.ensureJourneyState(booking, NO_SHOW_STATES, 'Cannot mark no-show in current state');
    const updated = await this.repo.markNoShow(bookingId, reason);
    if (!updated) throw Object.assign(new Error('Cannot mark no-show in current state'), { code: 'INVALID_STATE' });

    const timestamp = new Date().toISOString();
    await this.repo.appendEvent(bookingId, 'booking.no_show', { driverId, reason, timestamp });
    await publishBookingNoShow({
      bookingId,
      routeId: updated.route_id,
      passengerId: updated.passenger_id,
      driverId,
      tripId: updated.trip_id ?? '',
      reason,
      timestamp,
    });
    return this.normalizeBooking(updated)!;
  }

  async completeJourney(bookingId: string, actorId: string): Promise<BookingRow> {
    const booking = await this.getBookingForParticipantAction(bookingId, actorId);
    this.ensureJourneyState(booking, JOURNEY_COMPLETION_STATES, 'Cannot complete journey in current state');
    const updated = await this.repo.completeJourney(bookingId);
    if (!updated) throw Object.assign(new Error('Cannot complete journey in current state'), { code: 'INVALID_STATE' });

    const timestamp = new Date().toISOString();
    await this.repo.appendEvent(bookingId, 'booking.journey_completed', { actorId, timestamp });
    await publishBookingJourneyCompleted({
      bookingId,
      routeId: updated.route_id,
      passengerId: updated.passenger_id,
      driverId: updated.driver_id,
      tripId: updated.trip_id ?? booking.trip_id ?? '',
      timestamp,
    });
    await publishBookingCompleted({
      bookingId,
      routeId: updated.route_id,
      passengerId: updated.passenger_id,
      driverId: updated.driver_id,
      totalPrice: parseFloat(updated.total_price),
      driverEarnings: parseFloat(updated.driver_earnings),
      timestamp,
    });
    return this.normalizeBooking(updated)!;
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
    return this.normalizeBooking(updated)!;
  }

  async triggerEmergency(bookingId: string, reporterId: string, reason: string): Promise<BookingRow> {
    const booking = await this.repo.findById(bookingId);
    if (!booking) throw Object.assign(new Error('Booking not found'), { code: 'NOT_FOUND' });

    const reporterRole = booking.passenger_id === reporterId
      ? 'passenger'
      : (booking.driver_id === reporterId ? 'driver' : null);

    if (!reporterRole) throw Object.assign(new Error('Forbidden'), { code: 'FORBIDDEN' });

    await this.repo.appendEvent(bookingId, 'booking.emergency', { reportedBy: reporterId, reporterRole, reason });
    await publishBookingEmergency({
      bookingId,
      routeId: booking.route_id,
      passengerId: booking.passenger_id,
      driverId: booking.driver_id,
      reportedBy: reporterId,
      reporterRole,
      reason,
      timestamp: new Date().toISOString(),
    });

    return this.normalizeBooking(booking)!;
  }

  async getBooking(id: string): Promise<BookingRow | null> {
    return this.normalizeBooking(await this.repo.findById(id));
  }

  async getByCode(code: string): Promise<BookingRow | null> {
    return this.normalizeBooking(await this.repo.findByCode(code));
  }

  async listMyBookings(userId: string, role: 'passenger' | 'driver', limit = 20, offset = 0): Promise<BookingRow[]> {
    if (role === 'driver') return this.repo.listByDriver(userId, limit, offset);
    return this.repo.listByPassenger(userId, limit, offset);
  }

  async listDriverRouteOperations(routeId: string, driverId: string): Promise<BookingRow[]> {
    const bookings = await this.repo.listByRouteForDriver(routeId, driverId);
    const priority = (booking: BookingRow): number => {
      const state = this.normalizeJourneyState(booking.journey_state);
      switch (state) {
        case 'driver_arrived':
          return 0;
        case 'driver_approaching':
          return 1;
        case 'confirmed':
        case null:
          return 2;
        case 'in_transit':
          return 3;
        case 'dropped_off':
        case 'walking_to_destination':
          return 4;
        case 'completed':
          return 5;
        case 'no_show':
        case 'cancelled':
          return 6;
        default:
          return 7;
      }
    };

    return [...bookings].sort((a, b) => {
      const delta = priority(a) - priority(b);
      if (delta != 0) return delta;
      const aTime = a.estimated_pickup_time ?? a.created_at;
      const bTime = b.estimated_pickup_time ?? b.created_at;
      return aTime.getTime() - bTime.getTime();
    });
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
    await releaseSeats(booking.route_id, bookingId, 'PAYMENT_FAILED');
    logger.info({ bookingId }, 'Booking cancelled via payment.failed event');
  }
}
