import type { BookingRepository, LatraTripSourceRow } from '../repositories/booking.repository.js';
import { getDriverComplianceProfile, getVehicleComplianceRecord } from '../clients/user.grpc.client.js';
import { getRouteComplianceSnapshot } from '../clients/route.grpc.client.js';
import { getTrackedTripSnapshot } from '../clients/location.grpc.client.js';

export interface LatraTripRecord {
  trip_id: string;
  origin_coordinates: string;
  end_coordinates: string;
  start_time: string;
  end_time: string;
  total_fare_amount: number;
  trip_distance: number;
  rating: number;
  driver_earning: number;
  driver_license_number: string;
  vehicle_registration: string;
  validation_status: 'complete' | 'incomplete';
  missing_fields: string[];
  warnings: string[];
}

export interface LatraTripsResult {
  trips: LatraTripRecord[];
  incomplete: LatraTripRecord[];
  summary: {
    total: number;
    complete: number;
    incomplete: number;
  };
  next_cursor?: string;
}

export interface LatraComplianceStats {
  total_licensed_vehicles: number;
  total_trips_this_month: number;
  reporting_compliance_rate: number;
  last_report_submitted_at: string | null;
  missing: {
    coordinates: number;
    times: number;
    ratings: number;
    driver_license_or_vehicle: number;
  };
}

export interface LatraVehicleVerification {
  registration_number: string;
  verified: boolean;
  status: 'valid' | 'invalid';
  mock: true;
  latra_license_number: string | null;
  expires_at: string | null;
}

function parseDateRange(startDate: string, endDate: string): { start: Date; endExclusive: Date } {
  const start = new Date(`${startDate}T00:00:00.000Z`);
  const endExclusive = new Date(`${endDate}T00:00:00.000Z`);
  endExclusive.setUTCDate(endExclusive.getUTCDate() + 1);
  if (Number.isNaN(start.getTime()) || Number.isNaN(endExclusive.getTime()) || start >= endExclusive) {
    throw Object.assign(new Error('Invalid LATRA date range'), { code: 'VALIDATION_ERROR' });
  }
  return { start, endExclusive };
}

function formatLatraDateTime(value: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return [
    value.getUTCFullYear(),
    '-',
    pad(value.getUTCMonth() + 1),
    '-',
    pad(value.getUTCDate()),
    ' ',
    pad(value.getUTCHours()),
    ':',
    pad(value.getUTCMinutes()),
    ':',
    pad(value.getUTCSeconds()),
  ].join('');
}

function coordinatePair(lng: number | null, lat: number | null): string {
  if (lng == null || lat == null) return '';
  return `${lng},${lat}`;
}

function amount(value: string): number {
  return Math.round(Number.parseFloat(value) || 0);
}

function haversineMeters(startLat: number, startLng: number, endLat: number, endLng: number): number {
  const toRad = (degrees: number) => (degrees * Math.PI) / 180;
  const earthRadiusMeters = 6371000;
  const dLat = toRad(endLat - startLat);
  const dLng = toRad(endLng - startLng);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(startLat)) *
      Math.cos(toRad(endLat)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  return Math.round(earthRadiusMeters * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
}

function rating(row: LatraTripSourceRow): number {
  return row.passenger_rating ?? row.driver_rating ?? 0;
}

export class LatraComplianceService {
  constructor(private readonly repo: BookingRepository) {}

  async listTrips(params: {
    startDate: string;
    endDate: string;
    cursor?: string;
    limit?: number;
  }): Promise<LatraTripsResult> {
    const { start, endExclusive } = parseDateRange(params.startDate, params.endDate);
    const limit = Math.min(Math.max(params.limit ?? 100, 1), 500);
    const offset = params.cursor ? Number.parseInt(params.cursor, 10) : 0;
    const rows = await this.repo.listCompletedTripsForLatraReport({
      startDate: start,
      endDate: endExclusive,
      limit: limit + 1,
      offset: Number.isFinite(offset) ? offset : 0,
    });
    const pageRows = rows.slice(0, limit);
    const trips = await Promise.all(pageRows.map((row) => this.toLatraTrip(row)));
    return {
      trips,
      incomplete: trips.filter((trip) => trip.validation_status === 'incomplete'),
      summary: {
        total: trips.length,
        complete: trips.filter((trip) => trip.validation_status === 'complete').length,
        incomplete: trips.filter((trip) => trip.validation_status === 'incomplete').length,
      },
      next_cursor: rows.length > limit ? String((Number.isFinite(offset) ? offset : 0) + limit) : undefined,
    };
  }

  async getComplianceStats(now = new Date()): Promise<LatraComplianceStats> {
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const nextMonthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
    const [stats, rows] = await Promise.all([
      this.repo.getLatraComplianceStats(monthStart, nextMonthStart),
      this.repo.listCompletedTripsForLatraReport({
        startDate: monthStart,
        endDate: nextMonthStart,
        limit: 1000,
        offset: 0,
      }),
    ]);
    const reportRows = await Promise.all(rows.map((row) => this.toLatraTrip(row)));
    const complete = reportRows.filter((row) => row.validation_status === 'complete').length;
    const verifiedVehicles = new Set<string>(
      reportRows
        .filter((row) => row.vehicle_registration)
        .map((row) => row.vehicle_registration),
    );
    return {
      total_licensed_vehicles: verifiedVehicles.size,
      total_trips_this_month: stats.completed_trips_this_month,
      reporting_compliance_rate:
        stats.completed_trips_this_month === 0 ? 1 : complete / stats.completed_trips_this_month,
      last_report_submitted_at: null,
      missing: {
        coordinates: stats.trips_missing_coordinates,
        times: stats.trips_missing_times,
        ratings: stats.trips_missing_rating,
        driver_license_or_vehicle: reportRows.filter((row) =>
          row.missing_fields.includes('driver_license_number') ||
          row.missing_fields.includes('vehicle_registration'),
        ).length,
      },
    };
  }

  mockVerifyVehicle(registrationNumber: string): LatraVehicleVerification {
    const normalized = registrationNumber.trim().toUpperCase();
    const valid = /^[A-Z]{1,3}[ -]?\d{3,4}[A-Z]{0,2}$/.test(normalized);
    const expires = new Date();
    expires.setUTCFullYear(expires.getUTCFullYear() + 1);
    return {
      registration_number: normalized,
      verified: valid,
      status: valid ? 'valid' : 'invalid',
      mock: true,
      latra_license_number: valid ? `MOCK-LATRA-${normalized.replace(/[^A-Z0-9]/g, '')}` : null,
      expires_at: valid ? expires.toISOString().slice(0, 10) : null,
    };
  }

  mockOAuthToken() {
    return {
      access_token: 'mock-latra-access-token',
      token_type: 'Bearer',
      expires_in: 3600,
      scope: 'latra:read latra:vehicle_verify latra:report_submit',
      mock: true,
    };
  }

  private async toLatraTrip(row: LatraTripSourceRow): Promise<LatraTripRecord> {
    const [driver, route] = await Promise.all([
      getDriverComplianceProfile(row.driver_id),
      getRouteComplianceSnapshot(row.route_id),
    ]);
    const trackedTrip = row.trip_id ? await getTrackedTripSnapshot(row.trip_id) : null;
    const routeVehicle = route?.vehicleId ? await getVehicleComplianceRecord(route.vehicleId) : null;
    const fallbackVehicle = driver?.vehicles.find((v) => v.latraVerified) ?? driver?.vehicles[0] ?? null;
    const vehicle = routeVehicle ?? fallbackVehicle;
    const startLat = row.pickup_point_lat ?? row.pickup_lat;
    const startLng = row.pickup_point_lng ?? row.pickup_lng;
    const endLat = row.dropoff_point_lat ?? row.dropoff_lat;
    const endLng = row.dropoff_point_lng ?? row.dropoff_lng;
    const startTime = row.trip_started_at ?? row.created_at;
    const endTime = row.trip_completed_at ?? row.completed_at ?? row.journey_completed_at;
    const missing: string[] = [];
    const warnings: string[] = [];

    if (startLat == null || startLng == null) missing.push('origin_coordinates');
    if (endLat == null || endLng == null) missing.push('end_coordinates');
    if (!endTime) missing.push('end_time');
    if (!driver?.licenseNumber) missing.push('driver_license_number');
    if (!vehicle?.registrationNumber) missing.push('vehicle_registration');
    if (!row.passenger_rating && !row.driver_rating) warnings.push('rating_missing_defaulted_to_zero');
    if (!trackedTrip?.distanceMeters && !route?.distanceMeters && startLat != null && startLng != null && endLat != null && endLng != null) {
      warnings.push('trip_distance_calculated_from_pickup_dropoff_coordinates');
    }
    if (!trackedTrip && row.trip_id) warnings.push('tracked_trip_snapshot_unavailable');
    if (trackedTrip && trackedTrip.locationPointsRecorded === 0) warnings.push('tracked_trip_has_no_location_points');
    if (!route) warnings.push('route_snapshot_unavailable');
    if (!routeVehicle && fallbackVehicle) warnings.push('vehicle_registration_fell_back_to_driver_profile');
    if (vehicle && !vehicle.latraVerified) warnings.push('vehicle_not_latra_verified_by_user_service');

    return {
      trip_id: row.trip_id ?? row.booking_id,
      origin_coordinates: coordinatePair(startLng, startLat),
      end_coordinates: coordinatePair(endLng, endLat),
      start_time: formatLatraDateTime(startTime),
      end_time: endTime ? formatLatraDateTime(endTime) : '',
      total_fare_amount: amount(row.total_price),
      trip_distance: trackedTrip?.distanceMeters || route?.distanceMeters ||
        (startLat != null && startLng != null && endLat != null && endLng != null
          ? haversineMeters(startLat, startLng, endLat, endLng)
          : 0),
      rating: rating(row),
      driver_earning: amount(row.driver_earnings),
      driver_license_number: driver?.licenseNumber ?? '',
      vehicle_registration: vehicle?.registrationNumber ?? '',
      validation_status: missing.length === 0 ? 'complete' : 'incomplete',
      missing_fields: missing,
      warnings,
    };
  }
}
