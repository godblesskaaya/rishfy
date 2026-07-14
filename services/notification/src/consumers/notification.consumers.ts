import IORedis from 'ioredis';
import { getConsumer } from '../kafka.js';
import { logger } from '../logger.js';
import { NotificationService } from '../services/notification.service.js';

const svc = new NotificationService();

type EventPayload = Record<string, unknown>;

interface BookingCreatedPayload {
  bookingId: string;
  passengerId: string;
  driverId: string;
  confirmationCode: string;
  driverName?: string;
  departureTime?: string;
  suggestedPickupName?: string;
  suggestedPickupLat?: number;
  suggestedPickupLng?: number;
  estimatedPickupTime?: string;
}

interface BookingDeclinedPayload {
  bookingId: string;
  passengerId: string;
  driverId: string;
  reason: string;
}

interface PaymentPayload {
  bookingId: string;
  userId: string;
  amountTzs: number;
  providerReference?: string;
  confirmationCode?: string;
}

interface BookingCancelledPayload {
  bookingId: string;
  passengerId: string;
  driverId: string;
  cancelledBy: 'passenger' | 'driver' | 'system';
  driverName?: string;
  departureTime?: string;
}

interface BookingEmergencyPayload {
  bookingId: string;
  routeId: string;
  passengerId: string;
  driverId: string;
  reportedBy: string;
  reporterRole: 'passenger' | 'driver';
  reason: string;
}

interface JourneyPayload extends EventPayload {
  bookingId?: string;
  booking_id?: string;
  routeId?: string;
  route_id?: string;
  passengerId?: string;
  passenger_id?: string;
  driverId?: string;
  driver_id?: string;
  tripId?: string;
  trip_id?: string;
  pickupName?: string;
  pickup_name?: string;
  dropoffName?: string;
  dropoff_name?: string;
  reason?: string;
  timestamp?: string;
}

interface DriverArrivedPayload extends EventPayload {
  bookingId?: string;
  booking_id?: string;
  passengerId?: string;
  passenger_id?: string;
  driverId?: string;
  driver_id?: string;
  tripId?: string;
  trip_id?: string;
  arrivalLat?: number;
  arrival_lat?: number;
  arrivalLng?: number;
  arrival_lng?: number;
  pickupLat?: number;
  pickup_lat?: number;
  pickupLng?: number;
  pickup_lng?: number;
  pickupAddress?: string;
  pickup_address?: string;
  driverName?: string;
  driver_name?: string;
  arrivedAt?: string;
  arrived_at?: string;
}

interface DriverLocationPayload extends EventPayload {
  bookingId?: string;
  booking_id?: string;
  driverId?: string;
  driver_id?: string;
  tripId?: string;
  trip_id?: string;
  proximityState?: string;
  proximity_state?: string;
  activeStopType?: string;
  active_stop_type?: string;
}

const TOPICS = [
  'booking.created',
  'booking.confirmed',
  'booking.cancelled',
  'booking.declined',
  'booking.expired',
  'booking.emergency',
  'booking.journey_started',
  'driver.arrived_pickup',
  'passenger.boarded',
  'passenger.dropped_off',
  'passenger.walking_to_destination',
  'booking.journey_completed',
  'booking.no_show',
  'booking.rated',
  'payment.completed',
  'payment.failed',
  'driver.location_updated',
  'driver.arrived',
];

function unwrapEventData<T extends EventPayload>(payload: EventPayload): T {
  const nested = payload['data'];
  if (nested && typeof nested === 'object' && !Array.isArray(nested)) {
    return nested as T;
  }
  return payload as T;
}

function pickString(payload: EventPayload, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
  }
  return undefined;
}

function pickNumber(payload: EventPayload, keys: string[]): number | undefined {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
  }
  return undefined;
}

function getEventType(topic: string, payload: EventPayload): string {
  return pickString(payload, ['event_type']) ?? topic;
}

function getEnvelopeEventId(payload: EventPayload): string | undefined {
  return pickString(payload, ['event_id']);
}

function getJourneyContext(payload: EventPayload): {
  bookingId?: string;
  routeId?: string;
  passengerId?: string;
  driverId?: string;
  tripId?: string;
  pickupName?: string;
  dropoffName?: string;
  reason?: string;
  timestamp?: string;
} {
  const journey = unwrapEventData<JourneyPayload>(payload);
  return {
    bookingId: pickString(journey, ['bookingId', 'booking_id']),
    routeId: pickString(journey, ['routeId', 'route_id']),
    passengerId: pickString(journey, ['passengerId', 'passenger_id']),
    driverId: pickString(journey, ['driverId', 'driver_id']),
    tripId: pickString(journey, ['tripId', 'trip_id']),
    pickupName: pickString(journey, ['pickupName', 'pickup_name']),
    dropoffName: pickString(journey, ['dropoffName', 'dropoff_name']),
    reason: pickString(journey, ['reason']),
    timestamp: pickString(journey, ['timestamp']),
  };
}

function journeyData(
  d: ReturnType<typeof getJourneyContext>,
  journeyState: string,
): Record<string, unknown> {
  return {
    bookingId: d.bookingId,
    routeId: d.routeId,
    tripId: d.tripId,
    passengerId: d.passengerId,
    driverId: d.driverId,
    journeyState,
    timestamp: d.timestamp,
  };
}

export async function startNotificationConsumers(redis: IORedis): Promise<void> {
  const consumer = await getConsumer('notification-service');
  await consumer.subscribe({ topics: TOPICS, fromBeginning: false });

  await consumer.run({
    eachMessage: async ({ topic, message }) => {
      const raw = message.value?.toString();
      if (!raw) return;
      try {
        const p = JSON.parse(raw) as Record<string, unknown>;
        await routeEvent(topic, p, redis);
      } catch (err) {
        logger.error({ err, topic }, 'Notification consumer error');
      }
    },
  });

  logger.info('Notification Kafka consumers started');
}

async function routeEvent(topic: string, payload: EventPayload, redis: IORedis): Promise<void> {
  const enq = (params: Parameters<typeof svc.enqueue>[1]) => svc.enqueue(redis, params);
  const eventType = getEventType(topic, payload);
  const envelopeEventId = getEnvelopeEventId(payload);

  if (topic === 'booking.created') {
    const d = payload as unknown as BookingCreatedPayload;
    await enq({
      userId: d.passengerId,
      templateKey: 'booking.created',
      channels: ['push', 'sms', 'in_app'],
      vars: {
        confirmation_code: d.confirmationCode,
        driver_name: d.driverName ?? 'your driver',
        departure_time: d.departureTime ?? '',
      },
      sourceEventType: eventType,
      sourceEventId: d.bookingId,
      data: {
        bookingId: d.bookingId,
        driverId: d.driverId,
      },
    });

    await enq({
      userId: d.driverId,
      templateKey: 'booking.driver_new_booking',
      channels: ['push', 'in_app'],
      vars: {
        pickup_name: d.suggestedPickupName ?? 'along your route',
        estimated_pickup_time: d.estimatedPickupTime ?? '',
        confirmation_code: d.confirmationCode,
      },
      sourceEventType: eventType,
      sourceEventId: d.bookingId,
      data: {
        bookingId: d.bookingId,
        suggestedPickupLat: d.suggestedPickupLat,
        suggestedPickupLng: d.suggestedPickupLng,
      },
    });
    return;
  }

  if (topic === 'booking.declined') {
    const d = payload as unknown as BookingDeclinedPayload;
    await enq({
      userId: d.passengerId,
      templateKey: 'booking.declined',
      channels: ['push', 'sms', 'in_app'],
      vars: { reason: d.reason },
      fallbackTitle: 'Booking declined',
      fallbackBody: 'Your booking was declined by the driver. Your seat has been released - please search again.',
      sourceEventType: eventType,
      sourceEventId: d.bookingId,
      data: {
        bookingId: d.bookingId,
        driverId: d.driverId,
      },
    });
    return;
  }

  if (topic === 'payment.completed') {
    const d = payload as unknown as PaymentPayload;
    await enq({
      userId: d.userId,
      templateKey: 'payment.completed',
      channels: ['push', 'sms'],
      vars: {
        amount: d.amountTzs.toLocaleString(),
        provider_reference: d.providerReference ?? '',
        confirmation_code: d.confirmationCode ?? '',
      },
      sourceEventType: eventType,
      sourceEventId: d.bookingId,
      data: {
        bookingId: d.bookingId,
      },
    });
    return;
  }

  if (topic === 'payment.failed') {
    const d = payload as unknown as PaymentPayload;
    await enq({
      userId: d.userId,
      templateKey: 'payment.failed',
      channels: ['push', 'sms'],
      vars: { confirmation_code: d.confirmationCode ?? '' },
      sourceEventType: eventType,
      sourceEventId: d.bookingId,
      data: {
        bookingId: d.bookingId,
      },
    });
    return;
  }

  if (topic === 'booking.cancelled') {
    const d = payload as unknown as BookingCancelledPayload;
    if (d.cancelledBy === 'driver') {
      await enq({
        userId: d.passengerId,
        templateKey: 'booking.cancelled.by_driver',
        channels: ['push', 'sms', 'in_app'],
        vars: {
          driver_name: d.driverName ?? 'your driver',
          departure_time: d.departureTime ?? '',
        },
        sourceEventType: eventType,
        sourceEventId: d.bookingId,
        data: {
          bookingId: d.bookingId,
          driverId: d.driverId,
        },
      });
    } else if (d.cancelledBy === 'passenger') {
      await enq({
        userId: d.passengerId,
        templateKey: 'booking.cancelled.passenger',
        channels: ['push', 'in_app'],
        vars: {
          driver_name: d.driverName ?? 'your driver',
          departure_time: d.departureTime ?? '',
          refund_message: '',
        },
        sourceEventType: eventType,
        sourceEventId: d.bookingId,
        data: {
          bookingId: d.bookingId,
          driverId: d.driverId,
        },
      });
    }
    return;
  }

  if (topic === 'booking.emergency') {
    const d = payload as unknown as BookingEmergencyPayload;
    const responderId = d.reporterRole === 'passenger' ? d.driverId : d.passengerId;

    await enq({
      userId: responderId,
      templateKey: 'booking.emergency',
      channels: ['push', 'in_app'],
      vars: { booking_id: d.bookingId, reason: d.reason },
      fallbackTitle: 'Emergency alert',
      fallbackBody: 'Emergency reported on booking {{booking_id}}. Reason: {{reason}}. Please respond immediately.',
      sourceEventType: eventType,
      sourceEventId: d.bookingId,
      data: {
        bookingId: d.bookingId,
        routeId: d.routeId,
        reportedBy: d.reportedBy,
        reporterRole: d.reporterRole,
        reason: d.reason,
      },
    });

    await enq({
      userId: d.reportedBy,
      templateKey: 'booking.emergency',
      channels: ['in_app'],
      vars: { booking_id: d.bookingId },
      fallbackTitle: 'Emergency received',
      fallbackBody: 'Your emergency report for booking {{booking_id}} has been submitted.',
      sourceEventType: eventType,
      sourceEventId: d.bookingId,
      data: {
        bookingId: d.bookingId,
        routeId: d.routeId,
        reason: d.reason,
      },
    });
    return;
  }

  if (topic === 'passenger.boarded') {
    const d = getJourneyContext(payload);
    if (!d.passengerId) {
      logger.warn({ topic, payload }, 'Skipping boarded notification without passenger id');
      return;
    }

    await enq({
      userId: d.passengerId,
      templateKey: 'trip.started',
      channels: ['push'],
      vars: { driver_name: 'your driver' },
      sourceEventType: eventType,
      sourceEventId: d.bookingId ?? d.tripId ?? envelopeEventId,
      data: {
        ...journeyData(d, 'boarded'),
      },
    });
    return;
  }

  if (topic === 'driver.arrived_pickup') {
    const d = getJourneyContext(payload);
    if (!d.passengerId) {
      logger.warn({ topic, payload }, 'Skipping pickup arrival notification without passenger id');
      return;
    }

    await enq({
      userId: d.passengerId,
      templateKey: 'driver.arrived',
      channels: ['push', 'in_app'],
      vars: {
        driver_name: 'your driver',
        pickup_address: d.pickupName ?? 'your pickup point',
      },
      fallbackTitle: 'Driver arrived',
      fallbackBody: 'Your driver has arrived at {{pickup_address}}.',
      sourceEventType: eventType,
      sourceEventId: d.bookingId ?? d.tripId ?? envelopeEventId,
      data: {
        ...journeyData(d, 'driver_arrived'),
      },
    });
    return;
  }

  if (topic === 'passenger.dropped_off') {
    const d = getJourneyContext(payload);
    if (!d.passengerId) {
      logger.warn({ topic, payload }, 'Skipping dropoff notification without passenger id');
      return;
    }

    await enq({
      userId: d.passengerId,
      templateKey: 'passenger.dropped_off',
      channels: ['push', 'in_app'],
      vars: {
        dropoff_name: d.dropoffName ?? 'your drop-off point',
      },
      fallbackTitle: 'You have been dropped off',
      fallbackBody: 'Continue from {{dropoff_name}} to your final destination.',
      sourceEventType: eventType,
      sourceEventId: d.bookingId ?? d.tripId ?? envelopeEventId,
      data: {
        ...journeyData(d, 'dropped_off'),
      },
    });
    return;
  }

  if (topic === 'booking.journey_completed') {
    const d = getJourneyContext(payload);
    if (!d.passengerId) {
      logger.warn({ topic, payload }, 'Skipping journey completion notification without passenger id');
      return;
    }

    await enq({
      userId: d.passengerId,
      templateKey: 'trip.completed',
      channels: ['push', 'in_app'],
      vars: { driver_name: 'your driver' },
      sourceEventType: eventType,
      sourceEventId: d.bookingId ?? d.tripId ?? envelopeEventId,
      data: {
        ...journeyData(d, 'completed'),
      },
    });

    if (d.driverId) {
      await enq({
        userId: d.driverId,
        templateKey: 'driver.trip_completed',
        channels: ['push', 'in_app'],
        vars: {},
        fallbackTitle: 'Trip completed',
        fallbackBody: 'The passenger completed the journey. Your earnings will update shortly.',
        sourceEventType: eventType,
        sourceEventId: d.bookingId ?? d.tripId ?? envelopeEventId,
        data: {
          ...journeyData(d, 'completed'),
        },
      });
    }
    return;
  }

  if (topic === 'driver.arrived') {
    const d = unwrapEventData<DriverArrivedPayload>(payload);
    const passengerId = pickString(d, ['passengerId', 'passenger_id']);
    if (!passengerId) {
      logger.warn({ topic, payload }, 'Skipping arrival notification without passenger id');
      return;
    }

    const bookingId = pickString(d, ['bookingId', 'booking_id']);
    const tripId = pickString(d, ['tripId', 'trip_id']);
    const driverId = pickString(d, ['driverId', 'driver_id']);
    const pickupAddress = pickString(d, ['pickupAddress', 'pickup_address']) ?? 'your pickup point';

    await enq({
      userId: passengerId,
      templateKey: 'driver.arrived',
      channels: ['push'],
      vars: {
        driver_name: pickString(d, ['driverName', 'driver_name']) ?? 'your driver',
        pickup_address: pickupAddress,
      },
      fallbackTitle: 'Driver arrived',
      fallbackBody: 'Your driver has arrived at {{pickup_address}}.',
      sourceEventType: eventType,
      sourceEventId: bookingId ?? tripId ?? envelopeEventId,
      data: {
        bookingId,
        tripId,
        driverId,
        journeyState: 'driver_arrived',
        arrivalLat: pickNumber(d, ['arrivalLat', 'arrival_lat']),
        arrivalLng: pickNumber(d, ['arrivalLng', 'arrival_lng']),
        pickupLat: pickNumber(d, ['pickupLat', 'pickup_lat']),
        pickupLng: pickNumber(d, ['pickupLng', 'pickup_lng']),
        arrivedAt: pickString(d, ['arrivedAt', 'arrived_at']),
      },
    });
    return;
  }

  if (topic === 'booking.journey_started') {
    const d = getJourneyContext(payload);
    if (!d.passengerId) {
      logger.warn({ topic, payload }, 'Skipping journey start notification without passenger id');
      return;
    }

    await enq({
      userId: d.passengerId,
      templateKey: 'booking.journey_started',
      channels: ['in_app'],
      vars: {
        pickup_name: d.pickupName ?? 'your pickup point',
        dropoff_name: d.dropoffName ?? 'your destination',
      },
      fallbackTitle: 'Journey confirmed',
      fallbackBody: 'Your journey is confirmed from {{pickup_name}} to {{dropoff_name}}.',
      sourceEventType: eventType,
      sourceEventId: d.bookingId ?? d.tripId ?? envelopeEventId,
      data: {
        ...journeyData(d, 'waiting_for_driver'),
      },
    });
    return;
  }

  if (topic === 'booking.no_show') {
    const d = getJourneyContext(payload);
    if (!d.passengerId) {
      logger.warn({ topic, payload }, 'Skipping no-show notification without passenger id');
      return;
    }

    await enq({
      userId: d.passengerId,
      templateKey: 'booking.no_show',
      channels: ['push', 'in_app'],
      vars: { reason: d.reason ?? 'The driver marked this booking as a no-show.' },
      fallbackTitle: 'Booking closed as no-show',
      fallbackBody: '{{reason}}',
      sourceEventType: eventType,
      sourceEventId: d.bookingId ?? d.tripId ?? envelopeEventId,
      data: {
        ...journeyData(d, 'no_show'),
      },
    });
    return;
  }

  if (topic === 'driver.location_updated') {
    const d = unwrapEventData<DriverLocationPayload>(payload);
    logger.debug({
      eventType,
      bookingId: pickString(d, ['bookingId', 'booking_id']),
      tripId: pickString(d, ['tripId', 'trip_id']),
      driverId: pickString(d, ['driverId', 'driver_id']),
      proximityState: pickString(d, ['proximityState', 'proximity_state']),
      activeStopType: pickString(d, ['activeStopType', 'active_stop_type']),
    }, 'Parsed driver location telemetry envelope');
    return;
  }

  if (
    topic === 'passenger.walking_to_destination'
  ) {
    const d = getJourneyContext(payload);
    logger.debug({
      eventType,
      bookingId: d.bookingId,
      tripId: d.tripId,
      passengerId: d.passengerId,
      driverId: d.driverId,
    }, 'Parsed journey event without notification fan-out');
    return;
  }

  logger.debug({ topic }, 'No notification route registered for topic');
}
