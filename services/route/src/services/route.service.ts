import type { Pool } from 'pg';
import type { Redis } from 'ioredis';
import type { Producer } from 'kafkajs';
import polyline from '@mapbox/polyline';
import ngeohash from 'ngeohash';
import {
  RouteRepository,
  type RouteRunRow,
  type RouteRunStopRow,
  type RouteRunStopStatus,
  type SearchParams,
} from '../repositories/route.repository.js';
import { getDirections, getWalkingDistance, reverseGeocode } from '../clients/googlemaps.client.js';
import { listRouteBookings } from '../clients/booking.grpc.client.js';
import { completeTrackedRouteRun, startTrackedRouteRun } from '../clients/location.grpc.client.js';
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
  suggested_dropoff_point: { lat: number; lng: number; name: string | null };
  walking_distance_from_dropoff: number;
  walking_time_from_dropoff: number;
  driver_departure_time: Date;
  estimated_pickup_time: Date;
  available_seats: number;
  price_per_seat: string;
  walking_preference_meters: number;
  expanded_walking_limit_meters: number;
  walking_exceeds_preference: boolean;
  walking_overage_meters: number;
  time_difference_minutes: number;
  time_exceeds_preference: boolean;
  time_overage_minutes: number;
  match_quality: 'best' | 'good' | 'flexible';
  match_score: number;
  match_reasons: string[];
}

export interface DriverRouteOperation {
  booking_id: string;
  route_id: string;
  passenger_user_id: string;
  driver_user_id: string;
  seat_count: number;
  status: string;
  trip_status: string;
  journey_state: string;
  payment_id: string;
  trip_id: string;
  operational_priority: number;
}

export interface DriverRouteWorkspace {
  route: Awaited<ReturnType<RouteRepository['findById']>>;
  active_run: RouteRunRow | null;
  run_stops: RouteRunStopRow[];
  bookings: DriverRouteOperation[];
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

  private expandedWalkingLimit(preferredMeters: number) {
    return Math.min(
      5000,
      Math.max(preferredMeters + 750, Math.ceil(preferredMeters * 1.75)),
    );
  }

  private expandedTimeFlexMs(preferredFlexMs: number) {
    return Math.min(
      180 * 60_000,
      Math.max(preferredFlexMs + 15 * 60_000, Math.ceil(preferredFlexMs * 1.25)),
    );
  }

  private buildMatchMetadata(input: {
    pickupWalkMeters: number;
    dropoffWalkMeters: number;
    preferredWalkMeters: number;
    timeDifferenceMinutes: number;
    passengerFlexMinutes: number;
    availableSeats: number;
    seatsNeeded: number;
    pricePerSeat: string;
    driverRating: string | null;
  }) {
    const pickupOverage = Math.max(0, input.pickupWalkMeters - input.preferredWalkMeters);
    const dropoffOverage = Math.max(0, input.dropoffWalkMeters - input.preferredWalkMeters);
    const walkingOverage = pickupOverage + dropoffOverage;
    const totalWalkingMeters = input.pickupWalkMeters + input.dropoffWalkMeters;
    const price = Number.parseFloat(input.pricePerSeat);
    const rating = input.driverRating === null ? null : Number.parseFloat(input.driverRating);
    const seatSurplus = Math.max(0, input.availableSeats - input.seatsNeeded);

    const rankingScore =
      totalWalkingMeters / 60 +
      walkingOverage / 12 +
      input.timeDifferenceMinutes * 1.6 +
      (Number.isFinite(price) ? price / 2500 : 0) -
      Math.min(seatSurplus, 3) * 2 -
      (rating !== null && Number.isFinite(rating) ? Math.max(0, rating - 4) * 5 : 0);

    const matchScore = Math.max(0, Math.min(100, Math.round(100 - rankingScore)));
    const walkingExceedsPreference = walkingOverage > 0;
    const timeOverageMinutes = Math.max(0, input.timeDifferenceMinutes - input.passengerFlexMinutes);
    const timeExceedsPreference = timeOverageMinutes > 0;

    const matchQuality: SearchResult['match_quality'] =
      !walkingExceedsPreference &&
      !timeExceedsPreference &&
      input.timeDifferenceMinutes <= Math.ceil(input.passengerFlexMinutes / 2)
        ? 'best'
        : walkingOverage <= 500 && timeOverageMinutes <= 15
          ? 'good'
          : 'flexible';

    const matchReasons: string[] = [];
    if (walkingExceedsPreference) {
      matchReasons.push(`Walking is ${walkingOverage} m over your preference`);
    } else {
      matchReasons.push('Within preferred walking distance');
    }
    if (input.timeDifferenceMinutes === 0) {
      matchReasons.push('Pickup time matches your request');
    } else if (timeExceedsPreference) {
      matchReasons.push(`Pickup is ${timeOverageMinutes} min outside your time preference`);
    } else {
      matchReasons.push(`Pickup is ${input.timeDifferenceMinutes} min from your requested time`);
    }
    if (seatSurplus > 0) {
      matchReasons.push(`${seatSurplus} extra seat${seatSurplus === 1 ? '' : 's'} available`);
    }

    return {
      walking_exceeds_preference: walkingExceedsPreference,
      walking_overage_meters: walkingOverage,
      time_difference_minutes: input.timeDifferenceMinutes,
      time_exceeds_preference: timeExceedsPreference,
      time_overage_minutes: timeOverageMinutes,
      match_quality: matchQuality,
      match_score: matchScore,
      match_reasons: matchReasons,
      rankingScore,
    };
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

  async getDriverRouteOperations(driverId: string, routeId: string) {
    let route = await this.repo.findById(routeId);
    if (!route || route.driver_id !== driverId) {
      throw new AppError('ROUTE_NOT_FOUND', 404);
    }
    const bookings = await listRouteBookings(routeId);
    const operations = bookings
      .filter((booking) => booking.driver_user_id === driverId)
      .map((booking) => ({
        ...booking,
        operational_priority: this.routeOperationPriority(booking.journey_state, booking.status),
      }))
      .sort((a, b) => a.operational_priority - b.operational_priority);
    const activeRun = await this.repo.findOpenRunByRoute(routeId);
    const syncedRun = activeRun
      ? await this.syncActiveRouteRunLifecycle(activeRun, operations)
      : null;
    if (activeRun && !syncedRun) {
      route = await this.repo.findById(routeId);
    }
    const runStops = syncedRun
      ? await this.repo.listRouteRunStops(syncedRun.id)
      : [];

    return {
      route,
      active_run: syncedRun,
      run_stops: runStops,
      bookings: operations,
    } satisfies DriverRouteWorkspace;
  }

  async startRouteRun(driverId: string, routeId: string) {
    const route = await this.repo.findById(routeId);
    if (!route || route.driver_id !== driverId) {
      throw new AppError('ROUTE_NOT_FOUND', 404);
    }
    if (route.status === 'cancelled' || route.status === 'completed') {
      throw new AppError('ROUTE_NOT_ACTIVE', 409, 'Cannot start a run for an inactive route');
    }

    const existingRun = await this.repo.findOpenRunByRoute(routeId);
    if (existingRun) {
      const existingStops = await this.repo.listRouteRunStops(existingRun.id);
      if (existingStops.length > 0) {
        return this.getDriverRouteOperations(driverId, routeId);
      }
    }

    const run = existingRun ?? await this.repo.createRouteRun(routeId, driverId);
    const bookings = await listRouteBookings(routeId);
    const { stops: runStops, currentStopIndex } = this.normalizeRouteRunStops(
      this.buildRouteRunStops(bookings),
    );
    await this.repo.replaceRouteRunStops(run.id, runStops);
    await this.repo.updateRouteRunCurrentStopIndex(run.id, currentStopIndex);

    if (!existingRun) {
      await startTrackedRouteRun({
        routeRunId: run.id,
        routeId,
        driverUserId: driverId,
        originLat: route.origin_lat,
        originLng: route.origin_lng,
        destinationLat: route.destination_lat,
        destinationLng: route.destination_lng,
      });
    }

    return this.getDriverRouteOperations(driverId, routeId);
  }

  async advanceRouteRun(driverId: string, routeId: string) {
    const { route, run, stops } = await this.getOwnedOpenRun(driverId, routeId);
    const currentStop = this.selectCurrentStop(stops, run.current_stop_index);
    if (!currentStop) {
      await this.finalizeRouteRun(driverId, route, run, stops.length);
      return this.getDriverRouteOperations(driverId, routeId);
    }

    if (currentStop.status !== 'active') {
      await this.repo.clearActiveRouteRunStops(run.id);
      await this.repo.setRouteRunStopStatus(run.id, currentStop.sequence, 'active');
      await this.repo.updateRouteRunCurrentStopIndex(run.id, currentStop.sequence);
    }

    return this.getDriverRouteOperations(driverId, routeId);
  }

  async completeCurrentRouteRunStop(driverId: string, routeId: string) {
    const { route, run, stops } = await this.getOwnedOpenRun(driverId, routeId);
    const currentStop = this.selectCurrentStop(stops, run.current_stop_index);
    if (!currentStop) {
      await this.finalizeRouteRun(driverId, route, run, stops.length);
      return this.getDriverRouteOperations(driverId, routeId);
    }

    if (currentStop.status === 'pending') {
      await this.repo.clearActiveRouteRunStops(run.id);
    }

    await this.repo.setRouteRunStopStatus(run.id, currentStop.sequence, 'completed');

    const nextStop = this.selectNextOpenStop(stops, currentStop.sequence);
    if (!nextStop) {
      await this.finalizeRouteRun(driverId, route, run, currentStop.sequence + 1);
      return this.getDriverRouteOperations(driverId, routeId);
    }

    await this.repo.setRouteRunStopStatus(run.id, nextStop.sequence, 'active');
    await this.repo.updateRouteRunCurrentStopIndex(run.id, nextStop.sequence);
    return this.getDriverRouteOperations(driverId, routeId);
  }

  async completeRouteRun(driverId: string, routeId: string) {
    const { route, run, stops } = await this.getOwnedOpenRun(driverId, routeId);
    if (stops.some((stop) => stop.status === 'pending' || stop.status === 'active')) {
      throw new AppError(
        'ROUTE_RUN_NOT_FINISHED',
        409,
        'Complete or skip all remaining stops before finishing the route run',
      );
    }
    await this.finalizeRouteRun(driverId, route, run, stops.length);
    return this.getDriverRouteOperations(driverId, routeId);
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
    const preferredWalk = params.max_walking_distance_meters ?? 1000;
    const expandedWalkLimit = this.expandedWalkingLimit(preferredWalk);

    const stage12 = await this.repo.searchNearby({
      ...params,
      coarse_radius_meters: Math.max(config.COARSE_MATCH_RADIUS_METERS, expandedWalkLimit),
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
        const preferredFlexMs = passengerFlexMs + driverFlexMs;
        return Math.abs(r.estimated_pickup_time.getTime() - desiredTime.getTime()) <=
          this.expandedTimeFlexMs(preferredFlexMs);
      });

    // Stage 4: Walking distance via routing API with geohash cache
    const passengerFlexMinutes = params.time_flexibility_minutes ?? 30;
    const seatsNeeded = params.seats_needed ?? 1;
    const rankedResults: Array<SearchResult & { ranking_score: number }> = [];

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
      if (!pickupWalk || pickupWalk.distance_meters > expandedWalkLimit) continue;

      // Walking from dropoff
      const dropoffWalk = await this.cachedWalkingDistance(
        { lat: dropoffLat, lng: dropoffLng },
        { lat: params.dropoff_lat, lng: params.dropoff_lng },
      );
      if (!dropoffWalk || dropoffWalk.distance_meters > expandedWalkLimit) continue;

      // Reverse-geocode route-relative rendezvous names
      const pickupName = await this.cachedReverseGeocode(pickupLat, pickupLng);
      const dropoffName = await this.cachedReverseGeocode(dropoffLat, dropoffLng);
      const availableSeats = candidate.available_seats - candidate.booked_seats;
      const timeDifferenceMinutes = Math.round(
        Math.abs(candidate.estimated_pickup_time.getTime() - desiredTime.getTime()) / 60_000,
      );
      const metadata = this.buildMatchMetadata({
        pickupWalkMeters: pickupWalk.distance_meters,
        dropoffWalkMeters: dropoffWalk.distance_meters,
        preferredWalkMeters: preferredWalk,
        timeDifferenceMinutes,
        passengerFlexMinutes,
        availableSeats,
        seatsNeeded,
        pricePerSeat: candidate.price_per_seat,
        driverRating: candidate.driver_rating,
      });

      rankedResults.push({
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
        suggested_dropoff_point: { lat: dropoffLat, lng: dropoffLng, name: dropoffName },
        walking_distance_from_dropoff: dropoffWalk.distance_meters,
        walking_time_from_dropoff: dropoffWalk.duration_seconds,
        driver_departure_time: candidate.departure_time,
        estimated_pickup_time: candidate.estimated_pickup_time,
        available_seats: availableSeats,
        price_per_seat: candidate.price_per_seat,
        walking_preference_meters: preferredWalk,
        expanded_walking_limit_meters: expandedWalkLimit,
        walking_exceeds_preference: metadata.walking_exceeds_preference,
        walking_overage_meters: metadata.walking_overage_meters,
        time_difference_minutes: metadata.time_difference_minutes,
        time_exceeds_preference: metadata.time_exceeds_preference,
        time_overage_minutes: metadata.time_overage_minutes,
        match_quality: metadata.match_quality,
        match_score: metadata.match_score,
        match_reasons: metadata.match_reasons,
        ranking_score: metadata.rankingScore,
      });
    }

    // Stage 5: Rank by total passenger tradeoff, with walking still the dominant signal.
    rankedResults.sort((a, b) =>
      a.ranking_score - b.ranking_score ||
      a.walking_distance_to_pickup - b.walking_distance_to_pickup ||
      a.estimated_pickup_time.getTime() - b.estimated_pickup_time.getTime(),
    );
    const results: SearchResult[] = rankedResults.map((resultWithScore) => {
      const result = { ...resultWithScore };
      delete (result as Partial<typeof resultWithScore>).ranking_score;
      return result;
    });

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

  private routeOperationPriority(journeyState: string, status: string): number {
    switch ((journeyState || '').toLowerCase()) {
      case 'journey_state_driver_arrived':
        return 0;
      case 'journey_state_driver_approaching':
        return 1;
      case 'journey_state_confirmed':
      case '':
        return 2;
      case 'journey_state_in_transit':
      case 'journey_state_boarded':
        return 3;
      case 'journey_state_dropped_off':
      case 'journey_state_walking_to_destination':
        return 4;
      case 'journey_state_completed':
        return 5;
      case 'journey_state_no_show':
      case 'journey_state_cancelled':
        return 6;
      default:
        return status.toLowerCase() === 'booking_status_completed' ? 5 : 7;
    }
  }

  private async getOwnedOpenRun(driverId: string, routeId: string) {
    const route = await this.repo.findById(routeId);
    if (!route || route.driver_id !== driverId) {
      throw new AppError('ROUTE_NOT_FOUND', 404);
    }

    const run = await this.repo.findOpenRunByRoute(routeId);
    if (!run) {
      throw new AppError('ROUTE_RUN_NOT_ACTIVE', 409, 'No active route run for this route');
    }

    const bookings = await listRouteBookings(routeId);
    const driverBookings = bookings
      .filter((booking) => booking.driver_user_id === driverId)
      .map((booking) => ({
        ...booking,
        operational_priority: this.routeOperationPriority(booking.journey_state, booking.status),
      }))
      .sort((a, b) => a.operational_priority - b.operational_priority);
    const syncedRun = await this.syncActiveRouteRunLifecycle(run, driverBookings);
    if (!syncedRun) {
      throw new AppError('ROUTE_RUN_NOT_ACTIVE', 409, 'No active route run for this route');
    }

    const stops = await this.repo.listRouteRunStops(syncedRun.id);
    return { route, run: syncedRun, stops };
  }

  private selectCurrentStop(stops: RouteRunStopRow[], currentStopIndex: number): RouteRunStopRow | null {
    const activeStop = stops.find((stop) => stop.status === 'active');
    if (activeStop) {
      return activeStop;
    }

    const nextPending = stops.find(
      (stop) => stop.sequence >= currentStopIndex && stop.status === 'pending',
    );
    if (nextPending) {
      return nextPending;
    }

    return stops.find((stop) => stop.status === 'pending') ?? null;
  }

  private selectNextOpenStop(stops: RouteRunStopRow[], completedSequence: number): RouteRunStopRow | null {
    return stops.find(
      (stop) => stop.sequence > completedSequence && stop.status !== 'completed' && stop.status !== 'skipped',
    ) ?? null;
  }

  private normalizeRouteRunStops<T extends {
    sequence: number;
    status: RouteRunStopStatus;
  }>(stops: T[]) {
    const firstNonTerminal = stops.find((stop) => !this.isTerminalRouteRunStopStatus(stop.status));
    const currentStopIndex = firstNonTerminal?.sequence ?? stops.length;

    let activeAssigned = false;
    const normalizedStops = stops.map((stop) => {
      if (this.isTerminalRouteRunStopStatus(stop.status)) {
        return stop;
      }

      if (!activeAssigned && stop.sequence === currentStopIndex) {
        activeAssigned = true;
        return { ...stop, status: 'active' as const };
      }

      return { ...stop, status: 'pending' as const };
    });

    return { stops: normalizedStops, currentStopIndex };
  }

  private async syncActiveRouteRunLifecycle(
    run: RouteRunRow,
    bookings: DriverRouteOperation[],
  ): Promise<RouteRunRow | null> {
    const currentStops = await this.repo.listRouteRunStops(run.id);
    if (currentStops.length === 0) {
      return run;
    }

    const bookingDerivedStops = this.buildRouteRunStops(bookings);
    const derivedByKey = new Map(
      bookingDerivedStops.map((stop) => [`${stop.booking_id}:${stop.stop_kind}`, stop]),
    );

    const mergedStops = currentStops.map((stop) => {
      const derived = derivedByKey.get(`${stop.booking_id}:${stop.stop_kind}`);
      if (!derived) {
        return stop;
      }
      return {
        ...stop,
        stop_name: stop.stop_name ?? derived.stop_name ?? null,
        status: this.mergeRouteRunStopStatus(stop.status, derived.status),
      };
    });

    const { stops: normalizedStops, currentStopIndex } = this.normalizeRouteRunStops(mergedStops);

    for (const stop of normalizedStops) {
      const previous = currentStops.find((candidate) => candidate.id === stop.id);
      if (!previous || previous.status === stop.status) {
        continue;
      }
      await this.repo.updateRouteRunStopStatus(run.id, stop.id, stop.status);
    }

    let latestRun = run;
    if (run.current_stop_index !== currentStopIndex) {
      latestRun = await this.repo.updateRouteRunCurrentStopIndex(run.id, currentStopIndex) ?? latestRun;
    }

    if (!normalizedStops.some((stop) => this.isOpenRouteRunStopStatus(stop.status))) {
      const route = await this.repo.findById(run.route_id);
      if (route) {
        await this.finalizeRouteRun(run.driver_id, route, run, normalizedStops.length);
      }
      return null;
    }

    return latestRun;
  }

  private mergeRouteRunStopStatus(
    currentStatus: RouteRunStopStatus,
    derivedStatus: RouteRunStopStatus,
  ): RouteRunStopStatus {
    if (this.isTerminalRouteRunStopStatus(currentStatus)) {
      return currentStatus;
    }
    if (this.isTerminalRouteRunStopStatus(derivedStatus)) {
      return derivedStatus;
    }
    if (currentStatus === 'active') {
      return 'active';
    }
    return derivedStatus === 'active' ? 'active' : 'pending';
  }

  private isTerminalRouteRunStopStatus(status: RouteRunStopStatus): boolean {
    return status === 'completed' || status === 'skipped';
  }

  private isOpenRouteRunStopStatus(status: RouteRunStopStatus): boolean {
    return status === 'pending' || status === 'active';
  }

  private async finalizeRouteRun(
    driverId: string,
    route: NonNullable<Awaited<ReturnType<RouteRepository['findById']>>>,
    run: RouteRunRow,
    finalStopIndex: number,
  ): Promise<void> {
    await this.repo.updateRouteRunCurrentStopIndex(run.id, finalStopIndex);
    await completeTrackedRouteRun({
      routeRunId: run.id,
      endLat: route.destination_lat,
      endLng: route.destination_lng,
    });
    await this.repo.completeRouteRun(route.id, driverId);
    await this.repo.completeRoute(route.id, driverId);
    await this.redis.del(this.cacheKey(route.id));
  }

  private buildRouteRunStops(bookings: Array<{
    booking_id: string;
    pickup_address?: string;
    dropoff_address?: string;
    journey_state: string;
    status: string;
  }>): Array<{
    booking_id: string;
    stop_kind: 'pickup' | 'dropoff';
    sequence: number;
    status: 'pending' | 'active' | 'completed' | 'skipped';
    stop_name?: string | null;
  }> {
    const ranked = [...bookings].sort(
      (a, b) => this.routeOperationPriority(a.journey_state, a.status) -
          this.routeOperationPriority(b.journey_state, b.status),
    );

    const stops: Array<{
      booking_id: string;
      stop_kind: 'pickup' | 'dropoff';
      sequence: number;
      status: 'pending' | 'active' | 'completed' | 'skipped';
      stop_name?: string | null;
    }> = [];

    const pickupStopStatus = (journeyState: string): 'pending' | 'active' | 'completed' | 'skipped' => {
      switch (journeyState) {
        case 'JOURNEY_STATE_DRIVER_ARRIVED':
          return 'active';
        case 'JOURNEY_STATE_DRIVER_APPROACHING':
        case 'JOURNEY_STATE_CONFIRMED':
          return 'pending';
        case 'JOURNEY_STATE_IN_TRANSIT':
        case 'JOURNEY_STATE_DROPPED_OFF':
        case 'JOURNEY_STATE_WALKING_TO_DESTINATION':
        case 'JOURNEY_STATE_COMPLETED':
          return 'completed';
        case 'JOURNEY_STATE_CANCELLED':
        case 'JOURNEY_STATE_NO_SHOW':
          return 'skipped';
        default:
          return 'pending';
      }
    };

    const dropoffStopStatus = (journeyState: string): 'pending' | 'active' | 'completed' | 'skipped' => {
      switch (journeyState) {
        case 'JOURNEY_STATE_IN_TRANSIT':
          return 'active';
        case 'JOURNEY_STATE_DROPPED_OFF':
        case 'JOURNEY_STATE_WALKING_TO_DESTINATION':
        case 'JOURNEY_STATE_COMPLETED':
          return 'completed';
        case 'JOURNEY_STATE_CANCELLED':
        case 'JOURNEY_STATE_NO_SHOW':
          return 'skipped';
        default:
          return 'pending';
      }
    };

    let sequence = 0;
    for (const booking of ranked) {
      stops.push({
        booking_id: booking.booking_id,
        stop_kind: 'pickup',
        sequence: sequence++,
        status: pickupStopStatus(booking.journey_state),
        stop_name: booking.pickup_address ?? null,
      });
      stops.push({
        booking_id: booking.booking_id,
        stop_kind: 'dropoff',
        sequence: sequence++,
        status: dropoffStopStatus(booking.journey_state),
        stop_name: booking.dropoff_address ?? null,
      });
    }

    return stops;
  }
}
