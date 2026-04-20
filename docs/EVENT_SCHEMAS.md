# Rishfy Event Schemas

> **Kafka event catalog for async inter-service communication**
> Schema format: JSON (with planned migration to Avro/Protobuf)
> Delivery: At-least-once, consumers must be idempotent

---

## Table of Contents

1. [Event Design Principles](#1-event-design-principles)
2. [Envelope Format](#2-envelope-format)
3. [Topic Catalog](#3-topic-catalog)
4. [Event Schemas](#4-event-schemas)
5. [Consumer Patterns](#5-consumer-patterns)
6. [Error Handling](#6-error-handling)

---

## 1. Event Design Principles

### 1.1 Core Rules

| Rule | Rationale |
|------|-----------|
| **Events are facts, not commands** | Named in past tense (`booking.created`, not `create_booking`) |
| **Events include full context** | Consumer shouldn't need to call publisher to understand event |
| **Events are immutable** | Never edit; emit a correction event instead |
| **One event = one topic** | Don't multiplex event types on a single topic |
| **Publish after commit** | Use outbox pattern — never publish then write |
| **Schema evolution is additive** | Add fields, never remove or change type |

### 1.2 When to Publish an Event

✅ **Publish events for**:
- State changes other services care about (`booking.confirmed`)
- Fan-out scenarios (1 event → N consumers)
- Workflows decoupled from request-response
- Audit-worthy business events

❌ **Don't publish events for**:
- CRUD operations with no downstream interest
- Request-response flows (use gRPC)
- Real-time UI updates (use WebSocket)
- Internal service operations

### 1.3 Topic Naming

```
<bounded_context>.<entity>.<action>

Examples:
booking.created
booking.confirmed
booking.cancelled
payment.completed
payment.failed
trip.started
trip.completed
driver.location.updated
driver.arrived
```

---

## 2. Envelope Format

Every event uses a standard envelope:

```json
{
  "event_id": "evt_01HRZM8X9P2K3Q4R5S6T7U8V9W",
  "event_type": "booking.created",
  "event_version": "1.0",
  "timestamp": "2026-03-15T08:23:45.123Z",
  "source": {
    "service": "booking-service",
    "instance_id": "booking-svc-2a",
    "version": "1.2.3"
  },
  "trace_id": "abc123def456",
  "correlation_id": "req_xyz789",
  "data": {
    /* Event-specific payload */
  },
  "metadata": {
    "user_id": 123,
    "ip_address": "10.0.0.1"
  }
}
```

| Field | Description |
|-------|-------------|
| `event_id` | ULID, unique per event (idempotency key) |
| `event_type` | Topic name (duplicated for convenience) |
| `event_version` | Semantic version of schema |
| `timestamp` | ISO 8601 with milliseconds |
| `source` | Publisher identity |
| `trace_id` | OpenTelemetry trace ID for correlation |
| `correlation_id` | Request ID that triggered this event |
| `data` | Event payload (schema-specific) |
| `metadata` | Optional context (user, IP, etc.) |

---

## 3. Topic Catalog

| Topic | Publisher | Consumers | Purpose |
|-------|-----------|-----------|---------|
| `booking.created` | Booking | Notification | New booking awaiting payment |
| `booking.confirmed` | Booking | Notification, Location | Payment received, trip scheduled |
| `booking.cancelled` | Booking | Notification, Payment, Route | Booking cancelled (any actor) |
| `booking.expired` | Booking | Notification, Route | Pending booking expired without payment |
| `payment.initiated` | Payment | (logging/analytics) | STK push sent |
| `payment.completed` | Payment | Booking, Notification | Payment confirmed |
| `payment.failed` | Payment | Booking, Notification | Payment declined |
| `payment.refunded` | Payment | Booking, Notification | Refund completed |
| `trip.started` | Booking | Location, Notification | Driver picked up passenger |
| `trip.completed` | Booking | Payment, Notification, LATRA-Reporter | Trip ended, trigger payout & reporting |
| `trip.emergency_triggered` | Booking | Notification, Admin-Alerter | Passenger triggered emergency |
| `driver.location.updated` | Location | (optional analytics) | GPS update (high volume) |
| `driver.arrived` | Location | Notification, Booking | Driver at pickup point |
| `route.cancelled_by_driver` | Route | Booking, Notification | Driver cancelled route |
| `user.registered` | Auth | Notification | New user signed up |
| `user.driver_upgraded` | User | Notification | User became a driver |
| `rating.submitted` | Booking | User (update rating avg) | Rating recorded |

### Partitioning Strategy

| Topic | Partition Key | Partition Count | Retention |
|-------|---------------|-----------------|-----------|
| `booking.*` | `booking_id` | 12 | 30 days |
| `payment.*` | `booking_id` | 12 | 90 days |
| `trip.*` | `trip_id` | 12 | 90 days |
| `driver.location.updated` | `driver_id` | 24 | 24 hours |
| `driver.arrived` | `trip_id` | 6 | 7 days |
| `route.*` | `route_id` | 6 | 30 days |
| `user.*` | `user_id` | 6 | 30 days |
| `rating.*` | `user_id` | 6 | 90 days |

---

## 4. Event Schemas

### 4.1 `booking.created`

Published when a passenger creates a booking (before payment).

```json
{
  "event_type": "booking.created",
  "event_version": "1.0",
  "data": {
    "booking_id": 5678,
    "confirmation_code": "A1B2C3D4",
    "route_id": 1234,
    "passenger_id": 123,
    "driver_id": 45,
    "seats_booked": 2,
    "total_amount": 7000,
    "currency": "TZS",
    "departure_time": "2026-03-16T08:00:00.000Z",
    "pickup": {
      "lat": -6.7924,
      "lng": 39.2083,
      "address": "Mbezi Beach"
    },
    "dropoff": {
      "lat": -6.8162,
      "lng": 39.2803,
      "address": "Kariakoo"
    },
    "expires_at": "2026-03-15T08:25:45.000Z",
    "status": "pending"
  }
}
```

**Consumer Actions**:
- **Notification**: Send push to driver: "New booking received"

---

### 4.2 `booking.confirmed`

Published when payment completes and booking is locked in.

```json
{
  "event_type": "booking.confirmed",
  "event_version": "1.0",
  "data": {
    "booking_id": 5678,
    "confirmation_code": "A1B2C3D4",
    "route_id": 1234,
    "passenger_id": 123,
    "driver_id": 45,
    "seats_booked": 2,
    "total_amount": 7000,
    "platform_fee": 1050,
    "driver_earning": 5950,
    "payment_id": 9012,
    "payment_method": "m-pesa",
    "departure_time": "2026-03-16T08:00:00.000Z",
    "confirmed_at": "2026-03-15T08:24:32.000Z"
  }
}
```

**Consumer Actions**:
- **Notification**: Push + SMS to passenger and driver
- **Location**: Pre-cache driver for expected pickup

---

### 4.3 `booking.cancelled`

```json
{
  "event_type": "booking.cancelled",
  "event_version": "1.0",
  "data": {
    "booking_id": 5678,
    "route_id": 1234,
    "passenger_id": 123,
    "driver_id": 45,
    "seats_released": 2,
    "cancelled_by": {
      "user_id": 123,
      "actor_type": "passenger"
    },
    "reason": "Plans changed",
    "cancelled_at": "2026-03-15T09:00:00.000Z",
    "cancellation_charge": 0,
    "refund_amount": 7000,
    "refund_required": true,
    "was_paid": true
  }
}
```

**Consumer Actions**:
- **Route**: Increment `available_seats` by `seats_released`
- **Payment**: If `refund_required`, initiate refund
- **Notification**: Notify the OTHER party (not the canceller)

---

### 4.4 `booking.expired`

Published when pending booking expires (payment not completed in 2 min).

```json
{
  "event_type": "booking.expired",
  "event_version": "1.0",
  "data": {
    "booking_id": 5678,
    "route_id": 1234,
    "passenger_id": 123,
    "seats_to_release": 2,
    "expired_at": "2026-03-15T08:25:45.000Z"
  }
}
```

**Consumer Actions**:
- **Route**: Release reserved seats
- **Notification**: Optional: remind passenger to retry

---

### 4.5 `payment.completed`

```json
{
  "event_type": "payment.completed",
  "event_version": "1.0",
  "data": {
    "payment_id": 9012,
    "booking_id": 5678,
    "payer_id": 123,
    "amount": 7000,
    "currency": "TZS",
    "payment_method": "m-pesa",
    "transaction_reference": "RSH_2026031508234567_9012",
    "external_reference": "SGK4FXJ89L",
    "driver_earning": 5950,
    "platform_fee": 1050,
    "paid_at": "2026-03-15T08:24:32.000Z"
  }
}
```

**Consumer Actions**:
- **Booking**: Transition booking from `pending` → `confirmed`
- **Notification**: Send payment receipt to passenger

---

### 4.6 `payment.failed`

```json
{
  "event_type": "payment.failed",
  "event_version": "1.0",
  "data": {
    "payment_id": 9012,
    "booking_id": 5678,
    "payer_id": 123,
    "amount": 7000,
    "currency": "TZS",
    "payment_method": "m-pesa",
    "failure_code": "INSUFFICIENT_FUNDS",
    "failure_reason": "The payment was not completed due to insufficient funds.",
    "retry_allowed": true,
    "failed_at": "2026-03-15T08:24:45.000Z"
  }
}
```

**Consumer Actions**:
- **Booking**: Keep booking `pending` if retry allowed, else cancel
- **Notification**: Prompt passenger to retry payment

---

### 4.7 `payment.refunded`

```json
{
  "event_type": "payment.refunded",
  "event_version": "1.0",
  "data": {
    "refund_id": 321,
    "payment_id": 9012,
    "booking_id": 5678,
    "recipient_id": 123,
    "amount": 7000,
    "currency": "TZS",
    "reason": "Passenger cancelled 3+ hours before",
    "refund_type": "full",
    "refunded_at": "2026-03-15T09:05:00.000Z"
  }
}
```

---

### 4.8 `trip.started`

```json
{
  "event_type": "trip.started",
  "event_version": "1.0",
  "data": {
    "trip_id": 890,
    "booking_id": 5678,
    "route_id": 1234,
    "driver_id": 45,
    "passenger_id": 123,
    "start_lat": -6.7924,
    "start_lng": 39.2083,
    "started_at": "2026-03-16T08:02:00.000Z",
    "estimated_end_time": "2026-03-16T08:47:00.000Z"
  }
}
```

**Consumer Actions**:
- **Location**: Start tracking driver for this trip
- **Notification**: Alert passenger's emergency contact if configured

---

### 4.9 `trip.completed`

```json
{
  "event_type": "trip.completed",
  "event_version": "1.0",
  "data": {
    "trip_id": 890,
    "booking_id": 5678,
    "route_id": 1234,
    "driver_id": 45,
    "passenger_id": 123,
    "start_lat": -6.7924,
    "start_lng": 39.2083,
    "end_lat": -6.8162,
    "end_lng": 39.2803,
    "actual_distance_km": 12.8,
    "actual_duration_minutes": 47,
    "started_at": "2026-03-16T08:02:00.000Z",
    "ended_at": "2026-03-16T08:49:00.000Z",
    "total_fare": 7000,
    "driver_earning": 5950
  }
}
```

**Consumer Actions**:
- **Payment**: Queue driver payout
- **Notification**: Prompt both parties to rate
- **LATRA-Reporter**: Add to next daily report
- **User**: Increment `completed_trips` counter

---

### 4.10 `trip.emergency_triggered`

```json
{
  "event_type": "trip.emergency_triggered",
  "event_version": "1.0",
  "data": {
    "trip_id": 890,
    "booking_id": 5678,
    "passenger_id": 123,
    "driver_id": 45,
    "triggered_at": "2026-03-16T08:20:00.000Z",
    "lat": -6.8000,
    "lng": 39.2500,
    "notes": "Feeling unsafe"
  },
  "metadata": {
    "priority": "urgent"
  }
}
```

**Consumer Actions**:
- **Notification**: SMS to emergency contact immediately
- **Admin-Alerter**: Page on-call admin
- **Booking**: Flag trip as `disputed`

---

### 4.11 `driver.location.updated`

**High-volume topic**. Published every 30 seconds per active driver.

```json
{
  "event_type": "driver.location.updated",
  "event_version": "1.0",
  "data": {
    "driver_id": 45,
    "trip_id": 890,
    "lat": -6.8000,
    "lng": 39.2500,
    "bearing": 127,
    "speed": 12.5,
    "accuracy": 5.0,
    "timestamp": "2026-03-16T08:15:30.000Z"
  }
}
```

**Note**: Typically NOT consumed. WebSocket is the primary delivery mechanism. This topic exists for analytics/auditing.

---

### 4.12 `driver.arrived`

Published when Location Service detects driver within 100m of pickup.

```json
{
  "event_type": "driver.arrived",
  "event_version": "1.0",
  "data": {
    "driver_id": 45,
    "trip_id": 890,
    "booking_id": 5678,
    "passenger_id": 123,
    "arrival_lat": -6.7928,
    "arrival_lng": 39.2085,
    "pickup_lat": -6.7924,
    "pickup_lng": 39.2083,
    "distance_to_pickup_m": 45,
    "arrived_at": "2026-03-16T07:58:30.000Z"
  }
}
```

**Consumer Actions**:
- **Notification**: Push + SMS: "Your driver has arrived"
- **Booking**: Update trip status to `driver_arrived`

---

### 4.13 `route.cancelled_by_driver`

```json
{
  "event_type": "route.cancelled_by_driver",
  "event_version": "1.0",
  "data": {
    "route_id": 1234,
    "driver_id": 45,
    "reason": "Vehicle breakdown",
    "cancelled_at": "2026-03-15T18:00:00.000Z",
    "affected_bookings": [
      {"booking_id": 5678, "passenger_id": 123},
      {"booking_id": 5679, "passenger_id": 124}
    ]
  }
}
```

**Consumer Actions**:
- **Booking**: Auto-cancel all affected bookings
- **Notification**: Notify all affected passengers with refund info

---

### 4.14 `user.registered`

```json
{
  "event_type": "user.registered",
  "event_version": "1.0",
  "data": {
    "user_id": 123,
    "phone": "+255712345678",
    "user_type": "rider",
    "registered_at": "2026-03-15T08:00:00.000Z"
  }
}
```

**Consumer Actions**:
- **Notification**: Send welcome SMS/push

---

### 4.15 `user.driver_upgraded`

```json
{
  "event_type": "user.driver_upgraded",
  "event_version": "1.0",
  "data": {
    "user_id": 123,
    "driver_profile_id": 45,
    "license_number": "TZ-DL-2023-045678",
    "upgraded_at": "2026-03-15T10:00:00.000Z"
  }
}
```

---

### 4.16 `rating.submitted`

```json
{
  "event_type": "rating.submitted",
  "event_version": "1.0",
  "data": {
    "rating_id": 789,
    "trip_id": 890,
    "booking_id": 5678,
    "rater_id": 123,
    "rated_id": 45,
    "rater_type": "passenger",
    "rating_value": 5,
    "has_comment": true,
    "tags": ["punctual", "clean_car"],
    "submitted_at": "2026-03-16T09:00:00.000Z"
  }
}
```

**Consumer Actions**:
- **User**: Recalculate `rating_avg` and `rating_count` for rated user

---

## 5. Consumer Patterns

### 5.1 Idempotency

Every consumer must be idempotent. Check `event_id` in a processed-events table:

```typescript
async function handleEvent(event: Event) {
  const alreadyProcessed = await db.query(
    'SELECT 1 FROM processed_events WHERE event_id = $1',
    [event.event_id]
  );

  if (alreadyProcessed.rowCount > 0) {
    logger.info('Event already processed, skipping', { event_id: event.event_id });
    return;
  }

  await db.transaction(async (trx) => {
    // Do the actual work
    await processEventLogic(event, trx);
    // Record that we processed it
    await trx.query(
      'INSERT INTO processed_events (event_id, topic, processed_at) VALUES ($1, $2, NOW())',
      [event.event_id, event.event_type]
    );
  });
}
```

### 5.2 Consumer Group Strategy

| Service | Consumer Group | Topics Consumed |
|---------|---------------|-----------------|
| `booking-service` | `booking-consumer` | `payment.completed`, `payment.failed`, `payment.refunded`, `route.cancelled_by_driver` |
| `payment-service` | `payment-consumer` | `trip.completed`, `booking.cancelled` (for refunds) |
| `route-service` | `route-consumer` | `booking.cancelled`, `booking.expired` (to release seats) |
| `notification-service` | `notification-consumer` | Most topics (for delivering notifications) |
| `user-service` | `user-consumer` | `rating.submitted` (to update averages) |
| `location-service` | `location-consumer` | `trip.started`, `trip.completed` |
| `latra-reporter` | `latra-consumer` | `trip.completed` |

### 5.3 Processing Order

Use partition keys to ensure events for the same entity are processed in order:
- All `booking.*` events for booking 5678 go to the same partition (keyed by `booking_id`)
- This guarantees Kafka delivers them to the same consumer in order

### 5.4 Dead Letter Queue (DLQ)

If an event fails processing after 3 retries, it goes to a DLQ topic:

```
booking.created.dlq
payment.completed.dlq
...
```

Admin alerts are triggered when DLQ messages appear. Messages in DLQ can be manually reprocessed after fixing the root cause.

---

## 6. Error Handling

### 6.1 Retry Strategy

```typescript
const RETRY_CONFIG = {
  maxRetries: 3,
  initialDelayMs: 1000,
  maxDelayMs: 30000,
  backoffMultiplier: 2.0
};
```

Retries: 1s → 2s → 4s → 8s → DLQ

### 6.2 Poison Messages

If an event causes a consumer to crash 3+ times:
1. Log error with full event payload
2. Send to DLQ topic
3. Alert on-call engineer
4. Continue processing remaining messages

### 6.3 Monitoring Metrics

Every consumer exports these Prometheus metrics:

```
kafka_messages_consumed_total{topic="...", consumer_group="...", status="success|failed"}
kafka_consumer_lag{topic="...", partition="..."}
kafka_message_processing_duration_seconds{topic="..."}
kafka_dlq_messages_total{topic="..."}
```

Alerts fire when:
- Consumer lag > 1000 messages for > 5 minutes
- DLQ messages > 10 per hour
- Processing duration p95 > 5 seconds

---

## Quick Reference

### Publishing (Node.js + kafkajs)

```typescript
import { Kafka } from 'kafkajs';
import { ulid } from 'ulid';

const producer = kafka.producer();

async function publishBookingCreated(booking: Booking) {
  await producer.send({
    topic: 'booking.created',
    messages: [{
      key: String(booking.id),  // For partitioning
      value: JSON.stringify({
        event_id: `evt_${ulid()}`,
        event_type: 'booking.created',
        event_version: '1.0',
        timestamp: new Date().toISOString(),
        source: { service: 'booking-service', instance_id: process.env.INSTANCE_ID, version: '1.0.0' },
        trace_id: getCurrentTraceId(),
        correlation_id: getCurrentRequestId(),
        data: mapBookingToEvent(booking)
      })
    }]
  });
}
```

### Consuming

```typescript
const consumer = kafka.consumer({ groupId: 'notification-consumer' });

await consumer.subscribe({
  topics: ['booking.created', 'booking.confirmed', 'booking.cancelled'],
  fromBeginning: false
});

await consumer.run({
  eachMessage: async ({ topic, partition, message }) => {
    const event = JSON.parse(message.value!.toString());
    try {
      await handleEvent(event);
    } catch (error) {
      logger.error('Event processing failed', { error, event });
      throw error; // kafkajs will retry per config
    }
  }
});
```

---

**Document Owner**: Backend Team
**Last Updated**: 2026-03-15
**Version**: 1.0
**Status**: Approved for Development
