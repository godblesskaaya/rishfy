import type { Pool } from 'pg';
import { generateConfirmationCode } from '../utils/confirmation-code.js';

export type JourneyState =
  | 'confirmed'
  | 'driver_approaching'
  | 'driver_arrived'
  | 'boarded'
  | 'in_transit'
  | 'dropped_off'
  | 'walking_to_destination'
  | 'completed'
  | 'cancelled'
  | 'no_show';

export interface BookingRow {
  id: string;
  route_id: string;
  passenger_id: string;
  driver_id: string;
  seats_booked: number;
  seat_count: number;
  pickup_name: string | null;
  dropoff_name: string | null;
  pickup_lat: number | null;
  pickup_lng: number | null;
  dropoff_lat: number | null;
  dropoff_lng: number | null;
  // Matching-derived fields
  pickup_walking_distance: number | null;
  dropoff_walking_distance: number | null;
  pickup_walking_time: number | null;
  dropoff_walking_time: number | null;
  estimated_pickup_time: Date | null;
  suggested_pickup_name: string | null;
  suggested_dropoff_name: string | null;
  pickup_point_lat: number | null;
  pickup_point_lng: number | null;
  dropoff_point_lat: number | null;
  dropoff_point_lng: number | null;
  // status
  total_price: string;
  platform_fee: string;
  driver_earnings: string;
  status: 'pending' | 'confirmed' | 'declined' | 'driver_cancelled' | 'passenger_cancelled' | 'completed' | 'no_show';
  declined_reason: string | null;
  payment_status: 'unpaid' | 'paid' | 'refunded' | 'failed';
  payment_reference: string | null;
  payment_id: string | null;
  confirmation_code: string | null;
  idempotency_key: string | null;
  expires_at: Date | null;
  confirmed_at: Date | null;
  cancelled_at: Date | null;
  cancellation_reason: string | null;
  cancellation_policy: string | null;
  completed_at: Date | null;
  trip_started_at: Date | null;
  trip_completed_at: Date | null;
  passenger_rating: number | null;
  driver_rating: number | null;
  passenger_review: string | null;
  driver_review: string | null;
  created_at: Date;
  updated_at: Date;
  journey_state: JourneyState | null;
  trip_id: string | null;
  arrived_pickup_at: Date | null;
  boarded_at: Date | null;
  dropped_off_at: Date | null;
  journey_completed_at: Date | null;
  no_show_at: Date | null;
}

export interface SafetyReportRow {
  id: string;
  booking_id: string;
  route_id: string;
  passenger_id: string;
  driver_id: string;
  booking_status: BookingRow['status'];
  journey_state: JourneyState | null;
  payment_status: BookingRow['payment_status'];
  pickup_name: string | null;
  dropoff_name: string | null;
  payload: {
    reportedBy?: string;
    reporterRole?: 'passenger' | 'driver';
    reason?: string;
  } | null;
  created_at: Date;
}

export interface LatraTripSourceRow {
  booking_id: string;
  trip_id: string | null;
  route_id: string;
  passenger_id: string;
  driver_id: string;
  pickup_lat: number | null;
  pickup_lng: number | null;
  dropoff_lat: number | null;
  dropoff_lng: number | null;
  pickup_point_lat: number | null;
  pickup_point_lng: number | null;
  dropoff_point_lat: number | null;
  dropoff_point_lng: number | null;
  trip_started_at: Date | null;
  trip_completed_at: Date | null;
  completed_at: Date | null;
  journey_completed_at: Date | null;
  total_price: string;
  driver_earnings: string;
  passenger_rating: number | null;
  driver_rating: number | null;
  created_at: Date;
}

export interface LatraComplianceStatsRow {
  completed_trips_this_month: number;
  reportable_trips_this_month: number;
  trips_missing_coordinates: number;
  trips_missing_times: number;
  trips_missing_rating: number;
}

function normalizeJourneyState(journeyState: JourneyState | null): JourneyState | null {
  return journeyState === 'boarded' ? 'in_transit' : journeyState;
}

function normalizeBookingRow<T extends BookingRow | null>(booking: T): T {
  if (!booking || booking.journey_state !== 'boarded') {
    return booking;
  }

  return {
    ...booking,
    journey_state: normalizeJourneyState(booking.journey_state),
  };
}

const BOOKING_RETURNING = `
  *,
  ST_Y(pickup_point::geometry) AS pickup_point_lat,
  ST_X(pickup_point::geometry) AS pickup_point_lng,
  ST_Y(dropoff_point::geometry) AS dropoff_point_lat,
  ST_X(dropoff_point::geometry) AS dropoff_point_lng
`;

export class BookingRepository {
  constructor(private readonly pool: Pool) {}

  async create(data: {
    routeId: string;
    passengerId: string;
    driverId: string;
    seatsBooked: number;
    pickupName?: string;
    dropoffName?: string;
    pickupLat?: number;
    pickupLng?: number;
    dropoffLat?: number;
    dropoffLng?: number;
    pickupWalkingDistance?: number;
    dropoffWalkingDistance?: number;
    pickupWalkingTime?: number;
    dropoffWalkingTime?: number;
    estimatedPickupTime?: Date;
    suggestedPickupName?: string;
    suggestedDropoffName?: string;
    pickupPointLat?: number;
    pickupPointLng?: number;
    dropoffPointLat?: number;
    dropoffPointLng?: number;
    totalPrice: number;
    platformFee: number;
    driverEarnings: number;
    idempotencyKey: string;
    expiresAt: Date;
  }): Promise<BookingRow> {
    const code = generateConfirmationCode();
    const { rows } = await this.pool.query<BookingRow>(
      `INSERT INTO bookings (
        route_id, passenger_id, driver_id, seats_booked, seat_count,
        pickup_name, dropoff_name, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
        pickup_walking_distance, dropoff_walking_distance,
        pickup_walking_time, dropoff_walking_time,
        estimated_pickup_time, suggested_pickup_name, suggested_dropoff_name,
        pickup_point, dropoff_point,
        total_price, platform_fee, driver_earnings,
        status, payment_status, confirmation_code, idempotency_key, expires_at
      ) VALUES (
        $1,$2,$3,$4,$4,
        $5,$6,$7,$8,$9,$10,
        $11,$12,$13,$14,$15,$16,$17,
        CASE WHEN $18::double precision IS NOT NULL AND $19::double precision IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint($19,$18),4326)::geography ELSE NULL END,
        CASE WHEN $20::double precision IS NOT NULL AND $21::double precision IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint($21,$20),4326)::geography ELSE NULL END,
        $22,$23,$24,
        'pending','unpaid',$25,$26,$27
      )
      ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = now()
      RETURNING ${BOOKING_RETURNING}`,
      [
        data.routeId, data.passengerId, data.driverId, data.seatsBooked,
        data.pickupName ?? null, data.dropoffName ?? null,
        data.pickupLat ?? null, data.pickupLng ?? null,
        data.dropoffLat ?? null, data.dropoffLng ?? null,
        data.pickupWalkingDistance ?? null, data.dropoffWalkingDistance ?? null,
        data.pickupWalkingTime ?? null, data.dropoffWalkingTime ?? null,
        data.estimatedPickupTime ?? null,
        data.suggestedPickupName ?? null, data.suggestedDropoffName ?? null,
        data.pickupPointLat ?? null, data.pickupPointLng ?? null,
        data.dropoffPointLat ?? null, data.dropoffPointLng ?? null,
        data.totalPrice, data.platformFee, data.driverEarnings,
        code, data.idempotencyKey, data.expiresAt,
      ],
    );
    return normalizeBookingRow(rows[0]!)!;
  }

  async decline(bookingId: string, driverId: string, reason: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET status = 'declined', declined_reason = $3, updated_at = now()
       WHERE id = $1 AND driver_id = $2
         AND status = 'pending'
         AND created_at > now() - INTERVAL '10 minutes'
       RETURNING ${BOOKING_RETURNING}`,
      [bookingId, driverId, reason],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async findById(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `SELECT ${BOOKING_RETURNING} FROM bookings WHERE id=$1`,
      [id],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async findByCode(code: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `SELECT ${BOOKING_RETURNING} FROM bookings WHERE confirmation_code=$1`,
      [code],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async listByPassenger(passengerId: string, limit = 20, offset = 0): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      `SELECT ${BOOKING_RETURNING} FROM bookings WHERE passenger_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [passengerId, limit, offset],
    );
    return rows.map((row) => normalizeBookingRow(row)!);
  }

  async listByDriver(driverId: string, limit = 20, offset = 0): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      `SELECT ${BOOKING_RETURNING} FROM bookings WHERE driver_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [driverId, limit, offset],
    );
    return rows.map((row) => normalizeBookingRow(row)!);
  }

  async listByRoute(routeId: string): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      `SELECT ${BOOKING_RETURNING} FROM bookings WHERE route_id=$1 AND status NOT IN ('driver_cancelled','passenger_cancelled')`,
      [routeId],
    );
    return rows.map((row) => normalizeBookingRow(row)!);
  }

  async listByRouteForDriver(routeId: string, driverId: string): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      `SELECT ${BOOKING_RETURNING} FROM bookings
       WHERE route_id=$1
         AND driver_id=$2
         AND status NOT IN ('driver_cancelled','passenger_cancelled')
       ORDER BY created_at ASC`,
      [routeId, driverId],
    );
    return rows.map((row) => normalizeBookingRow(row)!);
  }

  async confirm(id: string, paymentId: string): Promise<BookingRow> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET status='confirmed', payment_status='paid', payment_id=$2,
       confirmed_at=now(), journey_state='confirmed', updated_at=now() WHERE id=$1 RETURNING ${BOOKING_RETURNING}`,
      [id, paymentId],
    );
    return normalizeBookingRow(rows[0]!)!;
  }

  async cancelByPassenger(id: string, reason: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET status='passenger_cancelled', cancellation_reason=$2,
       cancelled_at=now(), journey_state='cancelled', updated_at=now()
       WHERE id=$1
         AND (
           status='pending'
           OR (
             status='confirmed'
             AND (journey_state IS NULL OR journey_state IN ('confirmed', 'driver_approaching', 'driver_arrived'))
           )
         )
       RETURNING ${BOOKING_RETURNING}`,
      [id, reason],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async cancelByDriver(routeId: string): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET status='driver_cancelled', cancelled_at=now(), journey_state='cancelled', updated_at=now()
       WHERE route_id=$1
         AND (
           status='pending'
           OR (
             status='confirmed'
             AND (journey_state IS NULL OR journey_state IN ('confirmed', 'driver_approaching', 'driver_arrived'))
           )
         )
       RETURNING ${BOOKING_RETURNING}`,
      [routeId],
    );
    return rows.map((row) => normalizeBookingRow(row)!);
  }

  async markExpired(id: string): Promise<void> {
    await this.pool.query(
      `UPDATE bookings SET status='passenger_cancelled', cancellation_reason='EXPIRED',
       cancelled_at=now(), journey_state='cancelled', updated_at=now() WHERE id=$1 AND status='pending'`,
      [id],
    );
  }

  async markDriverArrived(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET journey_state='driver_arrived', arrived_pickup_at=COALESCE(arrived_pickup_at, now()), updated_at=now()
       WHERE id=$1
         AND status='confirmed'
         AND (journey_state IS NULL OR journey_state IN ('confirmed', 'driver_approaching'))
       RETURNING ${BOOKING_RETURNING}`,
      [id],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async startTrip(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET journey_state='driver_approaching', updated_at=now()
       WHERE id=$1
         AND status='confirmed'
         AND (journey_state IS NULL OR journey_state='confirmed')
       RETURNING ${BOOKING_RETURNING}`,
      [id],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async boardPassenger(id: string, tripId: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET journey_state='in_transit',
           trip_id=COALESCE(trip_id, $2),
           boarded_at=COALESCE(boarded_at, now()),
           trip_started_at=COALESCE(trip_started_at, now()),
           updated_at=now()
       WHERE id=$1
         AND status='confirmed'
          AND journey_state='driver_arrived'
        RETURNING ${BOOKING_RETURNING}`,
      [id, tripId],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async dropoffPassenger(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET journey_state='walking_to_destination',
           dropped_off_at=COALESCE(dropped_off_at, now()),
           trip_completed_at=COALESCE(trip_completed_at, now()),
           updated_at=now()
       WHERE id=$1
         AND status='confirmed'
         AND journey_state IN ('boarded', 'in_transit')
       RETURNING ${BOOKING_RETURNING}`,
      [id],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async completeJourney(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET status='completed',
           journey_state='completed',
           journey_completed_at=COALESCE(journey_completed_at, now()),
           completed_at=COALESCE(completed_at, now()),
           updated_at=now()
       WHERE id=$1
         AND (
           (status='confirmed' AND journey_state IN ('walking_to_destination', 'dropped_off'))
           OR (status='completed' AND journey_state='walking_to_destination')
         )
       RETURNING ${BOOKING_RETURNING}`,
      [id],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async completeLegacyTrip(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET status='completed',
           journey_state='completed',
           dropped_off_at=COALESCE(dropped_off_at, now()),
           trip_completed_at=COALESCE(trip_completed_at, now()),
           journey_completed_at=COALESCE(journey_completed_at, now()),
           completed_at=COALESCE(completed_at, now()),
           updated_at=now()
       WHERE id=$1
         AND status='confirmed'
         AND journey_state IN ('boarded', 'in_transit', 'walking_to_destination', 'dropped_off')
       RETURNING ${BOOKING_RETURNING}`,
      [id],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async markNoShow(id: string, reason: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET status='no_show',
           journey_state='no_show',
           no_show_at=COALESCE(no_show_at, now()),
           cancelled_at=COALESCE(cancelled_at, now()),
           cancellation_reason=$2,
           updated_at=now()
       WHERE id=$1
         AND status='confirmed'
          AND journey_state='driver_arrived'
        RETURNING ${BOOKING_RETURNING}`,
      [id, reason],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async submitRating(id: string, raterIsPassenger: boolean, rating: number, review: string): Promise<BookingRow | null> {
    const col = raterIsPassenger ? 'passenger_rating' : 'driver_rating';
    const reviewCol = raterIsPassenger ? 'passenger_review' : 'driver_review';
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET ${col}=$2, ${reviewCol}=$3, updated_at=now()
       WHERE id=$1 AND status='completed' AND ${col} IS NULL RETURNING ${BOOKING_RETURNING}`,
      [id, rating, review],
    );
    return normalizeBookingRow(rows[0] ?? null);
  }

  async appendEvent(bookingId: string, eventType: string, payload: unknown): Promise<void> {
    await this.pool.query(
      'INSERT INTO booking_events (booking_id, event_type, payload) VALUES ($1,$2,$3)',
      [bookingId, eventType, JSON.stringify(payload)],
    );
  }

  async listSafetyReportsForUser(userId: string): Promise<SafetyReportRow[]> {
    const { rows } = await this.pool.query<SafetyReportRow>(
      `SELECT be.id::text,
              be.booking_id,
              b.route_id,
              b.passenger_id,
              b.driver_id,
              b.status AS booking_status,
              b.journey_state,
              b.payment_status,
              b.pickup_name,
              b.dropoff_name,
              be.payload,
              be.created_at
       FROM booking_events be
       JOIN bookings b ON b.id = be.booking_id
       WHERE be.event_type='booking.emergency'
         AND (b.passenger_id=$1 OR b.driver_id=$1)
       ORDER BY be.created_at DESC`,
      [userId],
    );
    return rows;
  }

  async listCompletedTripsForLatraReport(params: {
    startDate: Date;
    endDate: Date;
    limit: number;
    offset: number;
  }): Promise<LatraTripSourceRow[]> {
    const { rows } = await this.pool.query<LatraTripSourceRow>(
      `SELECT b.id AS booking_id,
              b.trip_id,
              b.route_id,
              b.passenger_id,
              b.driver_id,
              b.pickup_lat,
              b.pickup_lng,
              b.dropoff_lat,
              b.dropoff_lng,
              ST_Y(b.pickup_point::geometry) AS pickup_point_lat,
              ST_X(b.pickup_point::geometry) AS pickup_point_lng,
              ST_Y(b.dropoff_point::geometry) AS dropoff_point_lat,
              ST_X(b.dropoff_point::geometry) AS dropoff_point_lng,
              b.trip_started_at,
              b.trip_completed_at,
              b.completed_at,
              b.journey_completed_at,
              b.total_price,
              b.driver_earnings,
              b.passenger_rating,
              b.driver_rating,
              b.created_at
       FROM bookings b
       WHERE b.status = 'completed'
         AND COALESCE(b.completed_at, b.journey_completed_at, b.trip_completed_at, b.updated_at) >= $1
         AND COALESCE(b.completed_at, b.journey_completed_at, b.trip_completed_at, b.updated_at) < $2
       ORDER BY COALESCE(b.completed_at, b.journey_completed_at, b.trip_completed_at, b.updated_at) ASC, b.id ASC
       LIMIT $3 OFFSET $4`,
      [params.startDate, params.endDate, params.limit, params.offset],
    );
    return rows;
  }

  async getLatraComplianceStats(monthStart: Date, nextMonthStart: Date): Promise<LatraComplianceStatsRow> {
    const { rows } = await this.pool.query<LatraComplianceStatsRow>(
      `SELECT COUNT(*)::int AS completed_trips_this_month,
              COUNT(*) FILTER (
                WHERE (pickup_point IS NOT NULL OR (pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL))
                  AND (dropoff_point IS NOT NULL OR (dropoff_lat IS NOT NULL AND dropoff_lng IS NOT NULL))
                  AND COALESCE(trip_started_at, confirmed_at, created_at) IS NOT NULL
                  AND COALESCE(trip_completed_at, completed_at, journey_completed_at) IS NOT NULL
              )::int AS reportable_trips_this_month,
              COUNT(*) FILTER (
                WHERE (pickup_point IS NULL AND (pickup_lat IS NULL OR pickup_lng IS NULL))
                   OR (dropoff_point IS NULL AND (dropoff_lat IS NULL OR dropoff_lng IS NULL))
              )::int AS trips_missing_coordinates,
              COUNT(*) FILTER (
                WHERE COALESCE(trip_started_at, confirmed_at, created_at) IS NULL
                   OR COALESCE(trip_completed_at, completed_at, journey_completed_at) IS NULL
              )::int AS trips_missing_times,
              COUNT(*) FILTER (
                WHERE passenger_rating IS NULL AND driver_rating IS NULL
              )::int AS trips_missing_rating
       FROM bookings
       WHERE status = 'completed'
         AND COALESCE(completed_at, journey_completed_at, trip_completed_at, updated_at) >= $1
         AND COALESCE(completed_at, journey_completed_at, trip_completed_at, updated_at) < $2`,
      [monthStart, nextMonthStart],
    );
    return rows[0] ?? {
      completed_trips_this_month: 0,
      reportable_trips_this_month: 0,
      trips_missing_coordinates: 0,
      trips_missing_times: 0,
      trips_missing_rating: 0,
    };
  }

  async markPaymentRefunded(id: string, policy: string): Promise<BookingRow> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET payment_status='refunded', cancellation_policy=$2, updated_at=now()
       WHERE id=$1 RETURNING ${BOOKING_RETURNING}`,
      [id, policy],
    );
    return normalizeBookingRow(rows[0]!)!;
  }
}
