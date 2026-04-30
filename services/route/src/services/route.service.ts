import type { Pool } from 'pg';
import type { Redis } from 'ioredis';
import type { Producer } from 'kafkajs';
import { RouteRepository, type SearchParams } from '../repositories/route.repository.js';
import { getDirections } from '../clients/googlemaps.client.js';
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
  recurrence?: 'none' | 'daily' | 'weekdays' | 'weekly' | 'custom';
  recurrence_days?: number[];
  recurrence_end_date?: string;
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
  private searchCacheKey(params: SearchParams) {
    return `route:search:${params.origin_lat}:${params.origin_lng}:${params.destination_lat}:${params.destination_lng}`;
  }

  async createRoute(driverId: string, input: CreateRouteInput) {
    const eligibility = await checkDriverEligibility(driverId);
    if (!eligibility.eligible) {
      throw new AppError('DRIVER_NOT_ELIGIBLE', 403, eligibility.blockers.join(', '));
    }

    const directions = await getDirections(
      { lat: input.origin_lat, lng: input.origin_lng },
      { lat: input.destination_lat, lng: input.destination_lng },
    );

    const driverProfile = await getUserProfile(driverId);

    const route = await this.repo.create({
      driver_id: driverId,
      vehicle_id: input.vehicle_id,
      origin_name: input.origin_name,
      destination_name: input.destination_name,
      polyline: directions?.polyline ?? null,
      distance_meters: directions?.distance_meters ?? null,
      duration_seconds: directions?.duration_seconds ?? null,
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
      ...(input as unknown as Record<string, unknown>),
    });

    // Generate recurring instances if needed
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

  async searchRoutes(params: SearchParams) {
    const cacheKey = this.searchCacheKey(params);
    const cached = await this.redis.get(cacheKey);
    if (cached) return JSON.parse(cached) as unknown[];

    const results = await this.repo.searchNearby({
      ...params,
      radius_meters: config.SEARCH_RADIUS_METERS,
    });

    await this.redis.setex(cacheKey, 60, JSON.stringify(results));
    return results;
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
