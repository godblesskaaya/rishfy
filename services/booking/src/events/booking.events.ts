import { getProducer } from '../kafka.js';
import { logger } from '../logger.js';

const T = {
  CREATED: 'booking.created',
  CONFIRMED: 'booking.confirmed',
  CANCELLED: 'booking.cancelled',
  DECLINED: 'booking.declined',
  EMERGENCY: 'booking.emergency',
  COMPLETED: 'booking.completed',
  EXPIRED: 'booking.expired',
  TRIP_STARTED: 'booking.trip_started',
  TRIP_COMPLETED: 'booking.trip_completed',
  RATED: 'booking.rated',
  JOURNEY_STARTED: 'booking.journey_started',
  ARRIVED_PICKUP: 'driver.arrived_pickup',
  PASSENGER_BOARDED: 'passenger.boarded',
  PASSENGER_DROPPED_OFF: 'passenger.dropped_off',
  WALKING_TO_DESTINATION: 'passenger.walking_to_destination',
  JOURNEY_COMPLETED: 'booking.journey_completed',
  NO_SHOW: 'booking.no_show',
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
  suggestedPickupName?: string;
  suggestedPickupLat?: number;
  suggestedPickupLng?: number;
  suggestedDropoffName?: string;
  suggestedDropoffLat?: number;
  suggestedDropoffLng?: number;
  estimatedPickupTime?: string;
}): Promise<void> { await pub(T.CREATED, data.bookingId, data); }

export async function publishBookingConfirmed(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  paymentId: string; confirmationCode: string; timestamp: string;
}): Promise<void> { await pub(T.CONFIRMED, data.bookingId, data); }

export async function publishBookingCancelled(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  cancelledBy: 'passenger' | 'driver' | 'system'; reason: string; timestamp: string;
}): Promise<void> { await pub(T.CANCELLED, data.bookingId, data); }

export async function publishBookingEmergency(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  reportedBy: string; reporterRole: 'passenger' | 'driver'; reason: string; timestamp: string;
}): Promise<void> { await pub(T.EMERGENCY, data.bookingId, data); }

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

export async function publishBookingJourneyStarted(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  tripId: string; pickupName: string; dropoffName: string; timestamp: string;
}): Promise<void> { await pub(T.JOURNEY_STARTED, data.bookingId, data); }

export async function publishDriverArrivedPickup(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  tripId: string; timestamp: string;
}): Promise<void> { await pub(T.ARRIVED_PICKUP, data.bookingId, data); }

export async function publishPassengerBoarded(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  tripId: string; timestamp: string;
}): Promise<void> { await pub(T.PASSENGER_BOARDED, data.bookingId, data); }

export async function publishPassengerDroppedOff(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  tripId: string; timestamp: string;
}): Promise<void> { await pub(T.PASSENGER_DROPPED_OFF, data.bookingId, data); }

export async function publishPassengerWalkingToDestination(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  tripId: string; timestamp: string;
}): Promise<void> { await pub(T.WALKING_TO_DESTINATION, data.bookingId, data); }

export async function publishBookingJourneyCompleted(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  tripId: string; timestamp: string;
}): Promise<void> { await pub(T.JOURNEY_COMPLETED, data.bookingId, data); }

export async function publishBookingNoShow(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  tripId: string; reason: string; timestamp: string;
}): Promise<void> { await pub(T.NO_SHOW, data.bookingId, data); }

export async function publishBookingRated(data: {
  bookingId: string; raterId: string; ratedId: string; rating: number; raterRole: 'passenger' | 'driver'; timestamp: string;
}): Promise<void> { await pub(T.RATED, data.bookingId, data); }

export async function publishBookingDeclined(data: {
  bookingId: string; routeId: string; passengerId: string; driverId: string;
  reason: string; timestamp: string;
}): Promise<void> { await pub(T.DECLINED, data.bookingId, data); }
