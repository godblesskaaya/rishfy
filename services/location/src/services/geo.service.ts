import type IORedis from 'ioredis';
import { config } from '../config.js';

const GEO_KEY = 'geo:active_drivers';

export interface DriverLocation {
  driverId: string;
  lat: number;
  lng: number;
  bearing?: number;
  speedKmh?: number;
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
    const R = 6371000;
    const φ1 = lat1 * Math.PI / 180;
    const φ2 = lat2 * Math.PI / 180;
    const Δφ = (lat2 - lat1) * Math.PI / 180;
    const Δλ = (lng2 - lng1) * Math.PI / 180;
    const a = Math.sin(Δφ / 2) ** 2 + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) ** 2;
    return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
}
