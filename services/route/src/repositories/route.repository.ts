import type { Pool } from 'pg';

export interface RouteRow {
  id: string;
  driver_id: string;
  vehicle_id: string;
  origin_name: string;
  origin_lat: number;
  origin_lng: number;
  destination_name: string;
  destination_lat: number;
  destination_lng: number;
  polyline: string | null;
  route_geometry_geojson: string | null;
  distance_meters: number | null;
  duration_seconds: number | null;
  flexibility_minutes: number;
  available_seats: number;
  booked_seats: number;
  price_per_seat: string;
  departure_time: Date;
  status: 'draft' | 'active' | 'full' | 'departed' | 'cancelled' | 'completed';
  recurrence: 'none' | 'daily' | 'weekdays' | 'weekly' | 'custom';
  recurrence_days: number[] | null;
  recurrence_end_date: Date | null;
  parent_route_id: string | null;
  driver_name: string | null;
  driver_rating: string | null;
  vehicle_make: string | null;
  vehicle_model: string | null;
  vehicle_color: string | null;
  vehicle_plate: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface SearchParams {
  pickup_lat: number;
  pickup_lng: number;
  dropoff_lat: number;
  dropoff_lng: number;
  desired_departure_time?: Date;
  time_flexibility_minutes?: number;
  max_walking_distance_meters?: number;
  seats_needed?: number;
  coarse_radius_meters?: number;
}

export interface SearchCandidate extends RouteRow {
  pickup_fraction: number;
  dropoff_fraction: number;
  closest_pickup_geojson: string;
  closest_dropoff_geojson: string;
}

export class RouteRepository {
  constructor(private readonly pool: Pool) {}

  async create(data: Omit<RouteRow, 'id' | 'booked_seats' | 'created_at' | 'updated_at' | 'route_geometry_geojson'> & {
    route_geometry_wkt?: string | null;
  }): Promise<RouteRow> {
    const { rows } = await this.pool.query<RouteRow & { route_geometry_geojson: string | null }>(
      `INSERT INTO routes (
        driver_id, vehicle_id, origin_name, origin_lat, origin_lng,
        destination_name, destination_lat, destination_lng,
        polyline, route_geometry, distance_meters, duration_seconds, flexibility_minutes,
        available_seats, price_per_seat, departure_time, status,
        recurrence, recurrence_days, recurrence_end_date, parent_route_id,
        driver_name, driver_rating, vehicle_make, vehicle_model, vehicle_color, vehicle_plate
      ) VALUES (
        $1, $2, $3, $4, $5,
        $6, $7, $8,
        $9, CASE WHEN $10::text IS NOT NULL THEN ST_GeogFromText($10) ELSE NULL END,
        $11, $12, $13,
        $14, $15, $16, $17,
        $18, $19, $20, $21,
        $22, $23, $24, $25, $26, $27
      ) RETURNING *, ST_AsGeoJSON(route_geometry) AS route_geometry_geojson`,
      [
        data.driver_id, data.vehicle_id, data.origin_name, data.origin_lat, data.origin_lng,
        data.destination_name, data.destination_lat, data.destination_lng,
        data.polyline, data.route_geometry_wkt ?? null,
        data.distance_meters, data.duration_seconds, data.flexibility_minutes ?? 15,
        data.available_seats, data.price_per_seat, data.departure_time, data.status,
        data.recurrence, data.recurrence_days, data.recurrence_end_date, data.parent_route_id,
        data.driver_name, data.driver_rating, data.vehicle_make, data.vehicle_model,
        data.vehicle_color, data.vehicle_plate,
      ],
    );
    return rows[0]!;
  }

  async findById(id: string): Promise<RouteRow | null> {
    const { rows } = await this.pool.query<RouteRow>(
      `SELECT *, ST_AsGeoJSON(route_geometry) AS route_geometry_geojson FROM routes WHERE id = $1`,
      [id],
    );
    return rows[0] ?? null;
  }

  async findByDriver(driverId: string, limit = 20, offset = 0): Promise<RouteRow[]> {
    const { rows } = await this.pool.query<RouteRow>(
      `SELECT *, ST_AsGeoJSON(route_geometry) AS route_geometry_geojson
       FROM routes WHERE driver_id = $1 ORDER BY departure_time DESC LIMIT $2 OFFSET $3`,
      [driverId, limit, offset],
    );
    return rows;
  }

  async update(id: string, driverId: string, data: Partial<RouteRow>): Promise<RouteRow | null> {
    const fields: string[] = [];
    const values: unknown[] = [];
    let idx = 1;
    const allowed: (keyof RouteRow)[] = ['origin_name', 'destination_name', 'available_seats',
      'price_per_seat', 'departure_time', 'status', 'recurrence', 'recurrence_days',
      'recurrence_end_date', 'flexibility_minutes'];
    for (const key of allowed) {
      if (data[key] !== undefined) { fields.push(`${key} = $${idx++}`); values.push(data[key]); }
    }
    if (fields.length === 0) return this.findById(id);
    fields.push('updated_at = now()');
    values.push(id, driverId);
    const { rows } = await this.pool.query<RouteRow>(
      `UPDATE routes SET ${fields.join(', ')} WHERE id = $${idx} AND driver_id = $${idx + 1}
       RETURNING *, ST_AsGeoJSON(route_geometry) AS route_geometry_geojson`,
      values,
    );
    return rows[0] ?? null;
  }

  async cancel(id: string, driverId: string): Promise<RouteRow | null> {
    const { rows } = await this.pool.query<RouteRow>(
      `UPDATE routes SET status = 'cancelled', updated_at = now()
       WHERE id = $1 AND driver_id = $2 AND status IN ('draft','active')
       RETURNING *, ST_AsGeoJSON(route_geometry) AS route_geometry_geojson`,
      [id, driverId],
    );
    return rows[0] ?? null;
  }

  // Stages 1 + 2: PostGIS coarse spatial filter + sequence validation in one CTE
  async searchNearby(params: SearchParams): Promise<SearchCandidate[]> {
    const seatsNeeded = params.seats_needed ?? 1;
    const coarseRadius = params.coarse_radius_meters ?? 3000;

    const { rows } = await this.pool.query<SearchCandidate>(
      `WITH stage1 AS (
        SELECT r.*,
          ST_AsGeoJSON(r.route_geometry) AS route_geometry_geojson,
          ST_LineLocatePoint(
            r.route_geometry::geometry,
            ST_SetSRID(ST_MakePoint($2, $1), 4326)
          ) AS pickup_fraction,
          ST_LineLocatePoint(
            r.route_geometry::geometry,
            ST_SetSRID(ST_MakePoint($4, $3), 4326)
          ) AS dropoff_fraction,
          ST_AsGeoJSON(
            ST_ClosestPoint(
              r.route_geometry::geometry,
              ST_SetSRID(ST_MakePoint($2, $1), 4326)
            )
          ) AS closest_pickup_geojson,
          ST_AsGeoJSON(
            ST_ClosestPoint(
              r.route_geometry::geometry,
              ST_SetSRID(ST_MakePoint($4, $3), 4326)
            )
          ) AS closest_dropoff_geojson
        FROM routes r
        WHERE r.status = 'active'
          AND (r.available_seats - r.booked_seats) >= $5
          AND r.route_geometry IS NOT NULL
          AND ST_DWithin(
            r.route_geometry,
            ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
            $6
          )
          AND ST_DWithin(
            r.route_geometry,
            ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography,
            $6
          )
      )
      SELECT * FROM stage1
      WHERE pickup_fraction < dropoff_fraction
      LIMIT 50`,
      [
        params.pickup_lat, params.pickup_lng,
        params.dropoff_lat, params.dropoff_lng,
        seatsNeeded, coarseRadius,
      ],
    );
    return rows;
  }

  async incrementBookedSeats(id: string, seats: number): Promise<void> {
    await this.pool.query(
      `UPDATE routes SET booked_seats = booked_seats + $2,
        status = CASE WHEN booked_seats + $2 >= available_seats THEN 'full' ELSE status END,
        updated_at = now()
       WHERE id = $1`,
      [id, seats],
    );
  }

  async reserveSeats(routeId: string, seatCount: number, _bookingId: string): Promise<{
    success: boolean;
    seatsRemaining: number;
    failureReason?: string;
  }> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const { rows } = await client.query<{ available_seats: number; booked_seats: number; status: string }>(
        `SELECT available_seats, booked_seats, status FROM routes WHERE id = $1 FOR UPDATE`,
        [routeId],
      );
      const route = rows[0];
      if (!route) {
        await client.query('ROLLBACK');
        return { success: false, seatsRemaining: 0, failureReason: 'ROUTE_NOT_FOUND' };
      }
      if (route.status !== 'active') {
        await client.query('ROLLBACK');
        return { success: false, seatsRemaining: route.available_seats - route.booked_seats, failureReason: 'ROUTE_NOT_ACTIVE' };
      }
      const free = route.available_seats - route.booked_seats;
      if (free < seatCount) {
        await client.query('ROLLBACK');
        return { success: false, seatsRemaining: free, failureReason: 'INSUFFICIENT_SEATS' };
      }
      const newBooked = route.booked_seats + seatCount;
      const newStatus = newBooked >= route.available_seats ? 'full' : 'active';
      await client.query(
        `UPDATE routes SET booked_seats = $2, status = $3, updated_at = now() WHERE id = $1`,
        [routeId, newBooked, newStatus],
      );
      await client.query('COMMIT');
      return { success: true, seatsRemaining: route.available_seats - newBooked };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async releaseSeats(routeId: string, seatCount: number): Promise<{
    success: boolean;
    seatsRemaining: number;
  }> {
    const { rows } = await this.pool.query<{ available_seats: number; booked_seats: number }>(
      `UPDATE routes
       SET booked_seats = GREATEST(0, booked_seats - $2),
           status = CASE
             WHEN status = 'full' AND booked_seats - $2 < available_seats THEN 'active'
             ELSE status
           END,
           updated_at = now()
       WHERE id = $1 AND status NOT IN ('cancelled','completed','departed')
       RETURNING available_seats, booked_seats`,
      [routeId, seatCount],
    );
    if (!rows[0]) return { success: false, seatsRemaining: 0 };
    const r = rows[0];
    return { success: true, seatsRemaining: r.available_seats - r.booked_seats };
  }
}
