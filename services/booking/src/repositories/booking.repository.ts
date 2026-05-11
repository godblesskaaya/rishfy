import type { Pool } from 'pg';
import { generateConfirmationCode } from '../utils/confirmation-code.js';

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
  estimated_pickup_time: Date | null;
  suggested_pickup_name: string | null;
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
}

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
    estimatedPickupTime?: Date;
    suggestedPickupName?: string;
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
        pickup_walking_distance, dropoff_walking_distance, pickup_walking_time,
        estimated_pickup_time, suggested_pickup_name,
        pickup_point, dropoff_point,
        total_price, platform_fee, driver_earnings,
        status, payment_status, confirmation_code, idempotency_key, expires_at
      ) VALUES (
        $1,$2,$3,$4,$4,
        $5,$6,$7,$8,$9,$10,
        $11,$12,$13,$14,$15,
        CASE WHEN $16::double precision IS NOT NULL AND $17::double precision IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint($17,$16),4326)::geography ELSE NULL END,
        CASE WHEN $18::double precision IS NOT NULL AND $19::double precision IS NOT NULL
             THEN ST_SetSRID(ST_MakePoint($19,$18),4326)::geography ELSE NULL END,
        $20,$21,$22,
        'pending','unpaid',$23,$24,$25
      )
      ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = now()
      RETURNING *`,
      [
        data.routeId, data.passengerId, data.driverId, data.seatsBooked,
        data.pickupName ?? null, data.dropoffName ?? null,
        data.pickupLat ?? null, data.pickupLng ?? null,
        data.dropoffLat ?? null, data.dropoffLng ?? null,
        data.pickupWalkingDistance ?? null, data.dropoffWalkingDistance ?? null,
        data.pickupWalkingTime ?? null, data.estimatedPickupTime ?? null,
        data.suggestedPickupName ?? null,
        data.pickupPointLat ?? null, data.pickupPointLng ?? null,
        data.dropoffPointLat ?? null, data.dropoffPointLng ?? null,
        data.totalPrice, data.platformFee, data.driverEarnings,
        code, data.idempotencyKey, data.expiresAt,
      ],
    );
    return rows[0]!;
  }

  async decline(bookingId: string, driverId: string, reason: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET status = 'declined', declined_reason = $3, updated_at = now()
       WHERE id = $1 AND driver_id = $2
         AND status = 'pending'
         AND created_at > now() - INTERVAL '10 minutes'
       RETURNING *`,
      [bookingId, driverId, reason],
    );
    return rows[0] ?? null;
  }

  async findById(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>('SELECT * FROM bookings WHERE id=$1', [id]);
    return rows[0] ?? null;
  }

  async findByCode(code: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>('SELECT * FROM bookings WHERE confirmation_code=$1', [code]);
    return rows[0] ?? null;
  }

  async listByPassenger(passengerId: string, limit = 20, offset = 0): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      'SELECT * FROM bookings WHERE passenger_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3',
      [passengerId, limit, offset],
    );
    return rows;
  }

  async listByDriver(driverId: string, limit = 20, offset = 0): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      'SELECT * FROM bookings WHERE driver_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3',
      [driverId, limit, offset],
    );
    return rows;
  }

  async listByRoute(routeId: string): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      'SELECT * FROM bookings WHERE route_id=$1 AND status NOT IN (\'driver_cancelled\',\'passenger_cancelled\')',
      [routeId],
    );
    return rows;
  }

  async confirm(id: string, paymentId: string): Promise<BookingRow> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET status='confirmed', payment_status='paid', payment_id=$2,
       confirmed_at=now(), updated_at=now() WHERE id=$1 RETURNING *`,
      [id, paymentId],
    );
    return rows[0]!;
  }

  async cancelByPassenger(id: string, reason: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET status='passenger_cancelled', cancellation_reason=$2,
       cancelled_at=now(), updated_at=now()
       WHERE id=$1 AND status IN ('pending','confirmed') RETURNING *`,
      [id, reason],
    );
    return rows[0] ?? null;
  }

  async cancelByDriver(routeId: string): Promise<BookingRow[]> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET status='driver_cancelled', cancelled_at=now(), updated_at=now()
       WHERE route_id=$1 AND status IN ('pending','confirmed') RETURNING *`,
      [routeId],
    );
    return rows;
  }

  async markExpired(id: string): Promise<void> {
    await this.pool.query(
      `UPDATE bookings SET status='passenger_cancelled', cancellation_reason='EXPIRED',
       cancelled_at=now(), updated_at=now() WHERE id=$1 AND status='pending'`,
      [id],
    );
  }

  async startTrip(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET trip_started_at=now(), updated_at=now() WHERE id=$1 AND status='confirmed' RETURNING *`,
      [id],
    );
    return rows[0] ?? null;
  }

  async completeTrip(id: string): Promise<BookingRow | null> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET status='completed', trip_completed_at=now(), completed_at=now(), updated_at=now()
       WHERE id=$1 AND trip_started_at IS NOT NULL RETURNING *`,
      [id],
    );
    return rows[0] ?? null;
  }

  async submitRating(id: string, raterIsPassenger: boolean, rating: number, review: string): Promise<BookingRow | null> {
    const col = raterIsPassenger ? 'passenger_rating' : 'driver_rating';
    const reviewCol = raterIsPassenger ? 'passenger_review' : 'driver_review';
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings SET ${col}=$2, ${reviewCol}=$3, updated_at=now()
       WHERE id=$1 AND status='completed' RETURNING *`,
      [id, rating, review],
    );
    return rows[0] ?? null;
  }

  async appendEvent(bookingId: string, eventType: string, payload: unknown): Promise<void> {
    await this.pool.query(
      'INSERT INTO booking_events (booking_id, event_type, payload) VALUES ($1,$2,$3)',
      [bookingId, eventType, JSON.stringify(payload)],
    );
  }

  async markPaymentRefunded(id: string, policy: string): Promise<BookingRow> {
    const { rows } = await this.pool.query<BookingRow>(
      `UPDATE bookings
       SET payment_status='refunded', cancellation_policy=$2, updated_at=now()
       WHERE id=$1 RETURNING *`,
      [id, policy],
    );
    return rows[0]!;
  }
}
