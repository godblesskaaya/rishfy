import type IORedis from 'ioredis';
import { config } from '../config.js';
import type { ActiveStopType, ProximityState, TripLiveState } from './live-trip.service.js';

const GEO_KEY = 'geo:active_drivers';

export interface DriverLocation {
  driverId: string;
  lat: number;
  lng: number;
  tripId?: string;
  routeRunId?: string;
  bookingId?: string;
  passengerId?: string;
  bearing?: number;
  speedKmh?: number;
  accuracyMeters?: number;
  timestamp?: string;
  activeStopType?: ActiveStopType;
  activeStopLat?: number | null;
  activeStopLng?: number | null;
  distanceToActiveStopMeters?: number | null;
  proximityState?: ProximityState;
  etaSeconds?: number | null;
  etaSource?: TripLiveState['etaSource'];
  updatedAt: string;
}

export class GeoService {
  constructor(private readonly redis: IORedis) {}

  async updateDriverLocation(data: DriverLocation): Promise<void> {
    await this.redis.geoadd(GEO_KEY, data.lng, data.lat, data.driverId);
    await this.redis.setex(
      `driver:loc:${data.driverId}`,
      config.DRIVER_ACTIVE_TTL_SECONDS,
      JSON.stringify(data),
    );
  }

  async removeDriver(driverId: string): Promise<void> {
    await this.redis.zrem(GEO_KEY, driverId);
    await this.redis.del(`driver:loc:${driverId}`);
  }

  async getDriverLocation(driverId: string): Promise<DriverLocation | null> {
    const raw = await this.redis.get(`driver:loc:${driverId}`);
    if (!raw) return null;
    return JSON.parse(raw) as DriverLocation;
  }

  async getNearbyDrivers(lat: number, lng: number, radiusKm = 5): Promise<string[]> {
    const results = await this.redis.georadius(GEO_KEY, lng, lat, radiusKm, 'km', 'ASC', 'COUNT', 20);
    return (results as string[]).filter(Boolean);
  }

  haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const radiusMeters = 6371000;
    const phi1 = lat1 * Math.PI / 180;
    const phi2 = lat2 * Math.PI / 180;
    const deltaPhi = (lat2 - lat1) * Math.PI / 180;
    const deltaLambda = (lng2 - lng1) * Math.PI / 180;
    const a = Math.sin(deltaPhi / 2) ** 2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) ** 2;
    return 2 * radiusMeters * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
}
