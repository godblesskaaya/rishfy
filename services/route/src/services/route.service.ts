import type { Pool } from 'pg';
import type { Redis } from 'ioredis';
import type { Producer } from 'kafkajs';
import polyline from '@mapbox/polyline';
import ngeohash from 'ngeohash';
import { RouteRepository, type SearchParams } from '../repositories/route.repository.js';
import { getDirections, getWalkingDistance, reverseGeocode } from '../clients/googlemaps.client.js';
import { checkDriverEligibility, getUserProfile } from '../clients/user.grpc.client.js';
import { publishRouteCancelled } from '../events/route.events.js';
import { AppError } from '../utils/errors.js';
import { config } from '../config.js';

interface CreateRouteInput {
  vehicle_id: string;
  origin_name: string;
  origin_lat: number;
  origin_lng: number;
  destination_name: string;
  destination_lat: number;
  destination_lng: number;
  available_seats: number;
  price_per_seat: number;
  departure_time: string;
  flexibility_minutes?: number;
  waypoints?: { lat: number; lng: number }[];
  recurrence?: 'none' | 'daily' | 'weekdays' | 'weekly' | 'custom';
  recurrence_days?: number[];
  recurrence_end_date?: string;
}

interface PreviewRouteInput {
  origin_lat: number;
  origin_lng: number;
  destination_lat: number;
  destination_lng: number;
  waypoints?: { lat: number; lng: number }[];
}

export interface SearchResult {
  route_id: string;
  driver_id: string;
  driver_name: string | null;
  driver_rating: string | null;
  vehicle_make: string | null;
  vehicle_model: string | null;
  vehicle_color: string | null;
  vehicle_plate: string | null;
  walking_distance_to_pickup: number;
  walking_time_to_pickup: number;
  suggested_pickup_point: { lat: number; lng: number; name: string | null };
  walking_distance_from_dropoff: number;
  walking_time_from_dropoff: number;
  driver_departure_time: Date;
  estimated_pickup_time: Date;
  available_seats: number;
  price_per_seat: string;
}

export class RouteService {
  private readonly repo: RouteRepository;

  constructor(
    pool: Pool,
    private readonly redis: Redis,
    private readonly kafkaProducer: Producer | null = null,
  ) {
    this.repo = new RouteRepository(pool);
  }

  private cacheKey(id: string) { return `route:${id}`; }

  private searchCacheKey(p: SearchParams) {
    return [
      'route:search',
      p.pickup_lat, p.pickup_lng,
      p.dropoff_lat, p.dropoff_lng,
      p.desired_departure_time?.getTime() ?? 0,
      p.time_flexibility_minutes ?? 30,
      p.max_walking_distance_meters ?? 1000,
      p.seats_needed ?? 1,
    ].join(':');
  }

  async previewRoute(input: PreviewRouteInput) {
    const directions = await getDirections(
      { lat: input.origin_lat, lng: input.origin_lng },
      { lat: input.destination_lat, lng: input.destination_lng },
      input.waypoints,
    );

    if (!directions) {
      throw new AppError('DIRECTIONS_UNAVAILABLE', 502, 'Could not compute route from routing API');
    }

    const coords = polyline.decode(directions.polyline);
    const geojsonLinestring = {
      type: 'LineString',
      coordinates: coords.map(([lat, lng]) => [lng, lat]),
    };

    return {
      polyline: directions.polyline,
      geojson_linestring: geojsonLinestring,
      distance_meters: directions.distance_meters,
      duration_seconds: directions.duration_seconds,
    };
  }

  async createRoute(driverId: string, input: CreateRouteInput) {
    const eligibility = await checkDriverEligibility(driverId);
    if (!eligibility.eligible) {
      throw new AppError('DRIVER_NOT_ELIGIBLE', 403, eligibility.blockers.join(', '));
    }

    const directions = await getDirections(
      { lat: input.origin_lat, lng: input.origin_lng },
      { lat: input.destination_lat, lng: input.destination_lng },
      input.waypoints,
    );

    const driverProfile = await getUserProfile(driverId);
    if (!driverProfile) throw new AppError('DRIVER_PROFILE_NOT_FOUND', 403, 'Could not load driver profile');

    let routeGeometryWkt: string | null = null;
    if (directions?.polyline) {
      const coords = polyline.decode(directions.polyline);
      const wktPoints = coords.map(([lat, lng]) => `${lng} ${lat}`).join(', ');
      routeGeometryWkt = `LINESTRING(${wktPoints})`;
    }

    const route = await this.repo.create({
      driver_id: driverProfile.userId,
      vehicle_id: input.vehicle_id,
      origin_name: input.origin_name,
      origin_lat: input.origin_lat,
      origin_lng: input.origin_lng,
      destination_name: input.destination_name,
      destination_lat: input.destination_lat,
      destination_lng: input.destination_lng,
      polyline: directions?.polyline ?? null,
      route_geometry_wkt: routeGeometryWkt,
      distance_meters: directions?.distance_meters ?? null,
      duration_seconds: directions?.duration_seconds ?? null,
      flexibility_minutes: input.flexibility_minutes ?? 15,
      available_seats: input.available_seats,
      price_per_seat: String(input.price_per_seat),
      departure_time: new Date(input.departure_time),
      status: 'active',
      recurrence: input.recurrence ?? 'none',
      recurrence_days: input.recurrence_days ?? null,
      recurrence_end_date: input.recurrence_end_date ? new Date(input.recurrence_end_date) : null,
      parent_route_id: null,
      driver_name: driverProfile ? `${driverProfile.firstName} ${driverProfile.lastName}`.trim() : null,
      driver_rating: driverProfile ? String(driverProfile.ratingAverage) : null,
      vehicle_make: null,
      vehicle_model: null,
      vehicle_color: null,
      vehicle_plate: null,
    });

    if (route.recurrence !== 'none' && route.recurrence_end_date) {
      void this.generateRecurrences(route.id, route);
    }

    return route;
  }

  async getRoute(id: string) {
    const cached = await this.redis.get(this.cacheKey(id));
    if (cached) return JSON.parse(cached) as ReturnType<RouteRepository['findById']>;

    const route = await this.repo.findById(id);
    if (!route) throw new AppError('ROUTE_NOT_FOUND', 404);

    await this.redis.setex(this.cacheKey(id), config.ROUTE_CACHE_TTL_SECONDS, JSON.stringify(route));
    return route;
  }

  async getDriverRoutes(driverId: string, limit = 20, offset = 0) {
    return this.repo.findByDriver(driverId, limit, offset);
  }

  async updateRoute(driverId: string, routeId: string, data: Partial<CreateRouteInput>) {
    const existing = await this.repo.findById(routeId);
    if (!existing) throw new AppError('ROUTE_NOT_FOUND', 404);
    if (existing.driver_id !== driverId) throw new AppError('FORBIDDEN', 403);

    const updated = await this.repo.update(routeId, driverId, {
      origin_name: data.origin_name,
      destination_name: data.destination_name,
      available_seats: data.available_seats,
      price_per_seat: data.price_per_seat !== undefined ? String(data.price_per_seat) : undefined,
      departure_time: data.departure_time ? new Date(data.departure_time) : undefined,
      flexibility_minutes: data.flexibility_minutes,
    });

    if (updated) {
      await this.redis.del(this.cacheKey(routeId));
    }
    return updated;
  }

  async cancelRoute(driverId: string, routeId: string) {
    const route = await this.repo.cancel(routeId, driverId);
    if (!route) throw new AppError('ROUTE_NOT_FOUND', 404);

    await this.redis.del(this.cacheKey(routeId));

    if (this.kafkaProducer) {
      await publishRouteCancelled(this.kafkaProducer, {
        route_id: route.id,
        driver_id: route.driver_id,
        departure_time: route.departure_time.toISOString(),
        cancelled_at: new Date().toISOString(),
      });
    }

    return route;
  }

  async searchRoutes(params: SearchParams): Promise<SearchResult[]> {
    const cacheKey = this.searchCacheKey(params);
    const cached = await this.redis.get(cacheKey);
    if (cached) return JSON.parse(cached) as SearchResult[];

    // Stages 1 + 2: PostGIS coarse spatial filter + sequence validation
    const stage12 = await this.repo.searchNearby({
      ...params,
      coarse_radius_meters: config.COARSE_MATCH_RADIUS_METERS,
    });

    // Stage 3: Temporal filter
    const desiredTime = params.desired_departure_time ?? new Date();
    const passengerFlexMs = (params.time_flexibility_minutes ?? 30) * 60_000;

    const stage3 = stage12
      .map(r => {
        const estimatedPickupMs =
          r.departure_time.getTime() + r.pickup_fraction * (r.duration_seconds ?? 0) * 1000;
        return { ...r, estimated_pickup_time: new Date(estimatedPickupMs) };
      })
      .filter(r => {
        const driverFlexMs = (r.flexibility_minutes ?? 15) * 60_000;
        return Math.abs(r.estimated_pickup_time.getTime() - desiredTime.getTime()) <= passengerFlexMs + driverFlexMs;
      });

    // Stage 4: Walking distance via routing API with geohash cache
    const maxWalk = params.max_walking_distance_meters ?? 1000;
    const results: SearchResult[] = [];

    for (const candidate of stage3) {
      const pickupCoords = JSON.parse(candidate.closest_pickup_geojson) as { coordinates: [number, number] };
      const dropoffCoords = JSON.parse(candidate.closest_dropoff_geojson) as { coordinates: [number, number] };
      const [pickupLng, pickupLat] = pickupCoords.coordinates;
      const [dropoffLng, dropoffLat] = dropoffCoords.coordinates;

      // Walking to pickup
      const pickupWalk = await this.cachedWalkingDistance(
        { lat: params.pickup_lat, lng: params.pickup_lng },
        { lat: pickupLat, lng: pickupLng },
      );
      if (!pickupWalk || pickupWalk.distance_meters > maxWalk) continue;

      // Walking from dropoff
      const dropoffWalk = await this.cachedWalkingDistance(
        { lat: dropoffLat, lng: dropoffLng },
        { lat: params.dropoff_lat, lng: params.dropoff_lng },
      );
      if (!dropoffWalk || dropoffWalk.distance_meters > maxWalk) continue;

      // Reverse-geocode suggested pickup name
      const pickupName = await this.cachedReverseGeocode(pickupLat, pickupLng);

      results.push({
        route_id: candidate.id,
        driver_id: candidate.driver_id,
        driver_name: candidate.driver_name,
        driver_rating: candidate.driver_rating,
        vehicle_make: candidate.vehicle_make,
        vehicle_model: candidate.vehicle_model,
        vehicle_color: candidate.vehicle_color,
        vehicle_plate: candidate.vehicle_plate,
        walking_distance_to_pickup: pickupWalk.distance_meters,
        walking_time_to_pickup: pickupWalk.duration_seconds,
        suggested_pickup_point: { lat: pickupLat, lng: pickupLng, name: pickupName },
        walking_distance_from_dropoff: dropoffWalk.distance_meters,
        walking_time_from_dropoff: dropoffWalk.duration_seconds,
        driver_departure_time: candidate.departure_time,
        estimated_pickup_time: candidate.estimated_pickup_time,
        available_seats: candidate.available_seats - candidate.booked_seats,
        price_per_seat: candidate.price_per_seat,
      });
    }

    // Stage 5: Rank by walking distance to pickup
    results.sort((a, b) => a.walking_distance_to_pickup - b.walking_distance_to_pickup);

    await this.redis.setex(cacheKey, 60, JSON.stringify(results));
    return results;
  }

  private async cachedWalkingDistance(
    origin: { lat: number; lng: number },
    destination: { lat: number; lng: number },
  ): Promise<{ distance_meters: number; duration_seconds: number } | null> {
    const key = `walk:${ngeohash.encode(origin.lat, origin.lng, 7)}:${ngeohash.encode(destination.lat, destination.lng, 7)}`;
    const cached = await this.redis.get(key);
    if (cached) return JSON.parse(cached) as { distance_meters: number; duration_seconds: number };

    const result = await getWalkingDistance(origin, destination);
    if (result) {
      await this.redis.setex(key, 3600, JSON.stringify(result));
    }
    return result;
  }

  private async cachedReverseGeocode(lat: number, lng: number): Promise<string | null> {
    const key = `revgeo:${ngeohash.encode(lat, lng, 7)}`;
    const cached = await this.redis.get(key);
    if (cached) return cached;

    const name = await reverseGeocode(lat, lng);
    if (name) {
      await this.redis.setex(key, 86400, name);
    }
    return name;
  }

  private async generateRecurrences(parentId: string, parent: Awaited<ReturnType<RouteRepository['findById']>>) {
    if (!parent || parent.recurrence === 'none' || !parent.recurrence_end_date) return;

    const endDate = new Date(parent.recurrence_end_date);
    const instances: Date[] = [];
    const cur = new Date(parent.departure_time);
    cur.setDate(cur.getDate() + 1);

    while (cur <= endDate && instances.length < 365) {
      const dayOfWeek = cur.getDay();
      let include = false;
      if (parent.recurrence === 'daily') include = true;
      else if (parent.recurrence === 'weekdays') include = dayOfWeek >= 1 && dayOfWeek <= 5;
      else if (parent.recurrence === 'weekly') include = dayOfWeek === new Date(parent.departure_time).getDay();
      else if (parent.recurrence === 'custom') include = (parent.recurrence_days ?? []).includes(dayOfWeek);
      if (include) instances.push(new Date(cur));
      cur.setDate(cur.getDate() + 1);
    }

    for (const departureTime of instances) {
      try {
        await this.repo.create({
          ...parent,
          route_geometry_wkt: null,
          departure_time: departureTime,
          recurrence: 'none',
          recurrence_days: null,
          recurrence_end_date: null,
          parent_route_id: parentId,
        });
      } catch {
        // Best-effort; don't fail the parent creation
      }
    }
  }
}
