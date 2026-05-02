import type { Pool } from 'pg';

export interface DriverLocationPoint {
  time: Date;
  driverId: string;
  tripId?: string;
  lat: number;
  lng: number;
  bearing?: number;
  speedKmh?: number;
  accuracyMeters?: number;
}

export interface TripRow {
  id: string;
  booking_id: string;
  driver_id: string;
  passenger_id: string;
  status: 'pending' | 'in_progress' | 'completed' | 'cancelled';
  origin_lat: number;
  origin_lng: number;
  destination_lat: number;
  destination_lng: number;
  path_encoded: string | null;
  total_distance_meters: number | null;
  total_duration_seconds: number | null;
  started_at: Date | null;
  completed_at: Date | null;
  cancelled_at: Date | null;
  created_at: Date;
  updated_at: Date;
}

export class LocationRepository {
  constructor(private readonly pool: Pool) {}

  async insertDriverLocation(point: DriverLocationPoint): Promise<void> {
    await this.pool.query(
      `INSERT INTO driver_locations (time, driver_id, trip_id, lat, lng, bearing, speed_kmh, accuracy_meters)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [
        point.time, point.driverId, point.tripId ?? null,
        point.lat, point.lng, point.bearing ?? null,
        point.speedKmh ?? null, point.accuracyMeters ?? null,
      ],
    );
  }

  async getLastKnownLocation(driverId: string): Promise<DriverLocationPoint | null> {
    const { rows } = await this.pool.query<DriverLocationPoint>(
      `SELECT time, driver_id as "driverId", trip_id as "tripId", lat, lng, bearing, speed_kmh as "speedKmh", accuracy_meters as "accuracyMeters"
       FROM driver_locations WHERE driver_id=$1 ORDER BY time DESC LIMIT 1`,
      [driverId],
    );
    return rows[0] ?? null;
  }

  async createTrip(data: {
    bookingId: string; driverId: string; passengerId: string;
    originLat: number; originLng: number; destinationLat: number; destinationLng: number;
  }): Promise<TripRow> {
    const { rows } = await this.pool.query<TripRow>(
      `INSERT INTO trips (booking_id, driver_id, passenger_id, origin_lat, origin_lng, destination_lat, destination_lng)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [data.bookingId, data.driverId, data.passengerId, data.originLat, data.originLng, data.destinationLat, data.destinationLng],
    );
    return rows[0]!;
  }

  async startTrip(bookingId: string): Promise<TripRow | null> {
    const { rows } = await this.pool.query<TripRow>(
      `UPDATE trips SET status='in_progress', started_at=now(), updated_at=now()
       WHERE booking_id=$1 AND status='pending' RETURNING *`,
      [bookingId],
    );
    return rows[0] ?? null;
  }

  async completeTrip(bookingId: string, pathEncoded: string | null, distanceMeters: number): Promise<TripRow | null> {
    const { rows } = await this.pool.query<TripRow>(
      `UPDATE trips SET status='completed', completed_at=now(), path_encoded=$2, total_distance_meters=$3, updated_at=now()
       WHERE booking_id=$1 AND status='in_progress' RETURNING *`,
      [bookingId, pathEncoded, distanceMeters],
    );
    return rows[0] ?? null;
  }

  async getRecentPath(tripId: string, limit = 500): Promise<DriverLocationPoint[]> {
    const { rows } = await this.pool.query<DriverLocationPoint>(
      `SELECT time, driver_id as "driverId", lat, lng, bearing FROM driver_locations
       WHERE trip_id=$1 ORDER BY time ASC LIMIT $2`,
      [tripId, limit],
    );
    return rows;
  }
}
