import { getProducer } from '../kafka.js';
import { logger } from '../logger.js';

const T = {
  CREATED: 'booking.created',
  CONFIRMED: 'booking.confirmed',
  CANCELLED: 'booking.cancelled',
  COMPLETED: 'booking.completed',
  EXPIRED: 'booking.expired',
  TRIP_STARTED: 'booking.trip_started',
  TRIP_COMPLETED: 'booking.trip_completed',
  RATED: 'booking.rated',
};

async function pub(topic: string, key: string, value: object): Promise<void> {
  try {
    const producer = await getProducer();
    await producer.send({ topic, messages: [{ key, value: JSON.stringify(value) }] });
  } catch (err) {
    logger.error({ err, topic }, 'Failed to publish booking event');
  }
}

export async function publishBookingCreated(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  seatsBooked: number; totalPrice: number; confirmationCode: string; timestamp: string;
}): Promise<void> { await pub(T.CREATED, data.bookingId, data); }

export async function publishBookingConfirmed(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  paymentId: string; confirmationCode: string; timestamp: string;
}): Promise<void> { await pub(T.CONFIRMED, data.bookingId, data); }

export async function publishBookingCancelled(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  cancelledBy: 'passenger' | 'driver' | 'system'; reason: string; timestamp: string;
}): Promise<void> { await pub(T.CANCELLED, data.bookingId, data); }

export async function publishBookingCompleted(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  totalPrice: number; driverEarnings: number; timestamp: string;
}): Promise<void> { await pub(T.COMPLETED, data.bookingId, data); }

export async function publishBookingExpired(data: {
  bookingId: string; routeId: string; passengerId: string; seatsBooked: number; timestamp: string;
}): Promise<void> { await pub(T.EXPIRED, data.bookingId, data); }

export async function publishTripStarted(data: {
  bookingId: string; driverId: string; passengerId: string; timestamp: string;
}): Promise<void> { await pub(T.TRIP_STARTED, data.bookingId, data); }

export async function publishTripCompleted(data: {
  bookingId: string; driverId: string; passengerId: string; driverEarnings: number; timestamp: string;
}): Promise<void> { await pub(T.TRIP_COMPLETED, data.bookingId, data); }

export async function publishBookingRated(data: {
  bookingId: string; raterId: string; ratedId: string; rating: number; raterRole: 'passenger' | 'driver'; timestamp: string;
}): Promise<void> { await pub(T.RATED, data.bookingId, data); }
