import type { DriverLocationPoint, TripRow } from '../repositories/location.repository.js';

export type ActiveStopType = 'pickup' | 'dropoff' | null;
export type ProximityState =
  | 'en_route_pickup'
  | 'approaching_pickup'
  | 'arrived_pickup'
  | 'en_route_dropoff'
  | 'approaching_dropoff'
  | 'arrived_dropoff'
  | 'trip_completed'
  | 'unknown';
export type RouteGeometrySource = 'trip_endpoints_linear_fallback' | 'none';

export interface TripLiveState {
  activeStopType: ActiveStopType;
  activeStopLat: number | null;
  activeStopLng: number | null;
  distanceToActiveStopMeters: number | null;
  proximityState: ProximityState;
  etaSeconds: number | null;
  etaSource: 'reported_speed' | 'fallback_speed' | 'none';
  currentRouteFraction: number | null;
  activeStopRouteFraction: number | null;
  remainingRouteFraction: number | null;
  routeGeometrySource: RouteGeometrySource;
}

const FALLBACK_SPEED_KMH = 30;
const MIN_REPORTED_SPEED_KMH = 3;

function clampFraction(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function roundFraction(value: number): number {
  return Number(clampFraction(value).toFixed(4));
}

function calculateCurrentRouteFraction(
  trip: TripRow,
  current: { lat: number; lng: number },
): number {
  const originLat = trip.origin_lat;
  const originLng = trip.origin_lng;
  const deltaLat = trip.destination_lat - originLat;
  const deltaLng = trip.destination_lng - originLng;
  const magnitudeSquared = (deltaLat ** 2) + (deltaLng ** 2);

  if (magnitudeSquared === 0) {
    return 0;
  }

  const projection = (
    ((current.lat - originLat) * deltaLat) + ((current.lng - originLng) * deltaLng)
  ) / magnitudeSquared;

  return roundFraction(projection);
}

function buildRouteGeometry(
  trip: TripRow | null,
  current: { lat: number; lng: number },
  activeStopType: ActiveStopType,
): Pick<
  TripLiveState,
  'currentRouteFraction' | 'activeStopRouteFraction' | 'remainingRouteFraction' | 'routeGeometrySource'
> {
  if (!trip || !activeStopType) {
    return {
      currentRouteFraction: null,
      activeStopRouteFraction: null,
      remainingRouteFraction: null,
      routeGeometrySource: 'none',
    };
  }

  const currentRouteFraction = calculateCurrentRouteFraction(trip, current);
  const activeStopRouteFraction = activeStopType === 'pickup' ? 0 : 1;

  return {
    currentRouteFraction,
    activeStopRouteFraction,
    remainingRouteFraction: roundFraction(Math.abs(activeStopRouteFraction - currentRouteFraction)),
    routeGeometrySource: 'trip_endpoints_linear_fallback',
  };
}

export function haversineDistanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const radiusMeters = 6371000;
  const phi1 = lat1 * Math.PI / 180;
  const phi2 = lat2 * Math.PI / 180;
  const deltaPhi = (lat2 - lat1) * Math.PI / 180;
  const deltaLambda = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(deltaPhi / 2) ** 2
    + Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) ** 2;
  return 2 * radiusMeters * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function estimateEtaSeconds(
  distanceMeters: number | null,
  speedKmh?: number | null,
): { seconds: number | null; source: TripLiveState['etaSource'] } {
  if (distanceMeters == null) {
    return { seconds: null, source: 'none' };
  }

  const normalizedSpeedKmh = speedKmh && speedKmh >= MIN_REPORTED_SPEED_KMH
    ? speedKmh
    : FALLBACK_SPEED_KMH;

  const metersPerSecond = normalizedSpeedKmh / 3.6;
  const seconds = Math.max(0, Math.round(distanceMeters / metersPerSecond));

  return {
    seconds,
    source: speedKmh && speedKmh >= MIN_REPORTED_SPEED_KMH ? 'reported_speed' : 'fallback_speed',
  };
}

export function deriveTripLiveState(
  trip: TripRow | null,
  current: { lat: number; lng: number; speedKmh?: number | null },
  arrivalRadiusMeters: number,
): TripLiveState {
  if (!trip) {
    return {
      activeStopType: null,
      activeStopLat: null,
      activeStopLng: null,
      distanceToActiveStopMeters: null,
      proximityState: 'unknown',
      etaSeconds: null,
      etaSource: 'none',
      currentRouteFraction: null,
      activeStopRouteFraction: null,
      remainingRouteFraction: null,
      routeGeometrySource: 'none',
    };
  }

  if (trip.status === 'completed') {
    return {
      activeStopType: null,
      activeStopLat: null,
      activeStopLng: null,
      distanceToActiveStopMeters: 0,
      proximityState: 'trip_completed',
      etaSeconds: 0,
      etaSource: 'none',
      currentRouteFraction: 1,
      activeStopRouteFraction: 1,
      remainingRouteFraction: 0,
      routeGeometrySource: 'trip_endpoints_linear_fallback',
    };
  }

  const pickupDistanceMeters = haversineDistanceMeters(
    current.lat,
    current.lng,
    trip.origin_lat,
    trip.origin_lng,
  );
  const dropoffDistanceMeters = haversineDistanceMeters(
    current.lat,
    current.lng,
    trip.destination_lat,
    trip.destination_lng,
  );

  const approachRadiusMeters = Math.max(arrivalRadiusMeters * 5, 500);
  const pickupArrived = pickupDistanceMeters <= arrivalRadiusMeters;
  const dropoffArrived = dropoffDistanceMeters <= arrivalRadiusMeters;

  if (!pickupArrived) {
    const eta = estimateEtaSeconds(pickupDistanceMeters, current.speedKmh);
    const geometry = buildRouteGeometry(trip, current, 'pickup');
    return {
      activeStopType: 'pickup',
      activeStopLat: trip.origin_lat,
      activeStopLng: trip.origin_lng,
      distanceToActiveStopMeters: Math.round(pickupDistanceMeters),
      proximityState: pickupDistanceMeters <= approachRadiusMeters ? 'approaching_pickup' : 'en_route_pickup',
      etaSeconds: eta.seconds,
      etaSource: eta.source,
      ...geometry,
    };
  }

  if (!dropoffArrived) {
    const eta = estimateEtaSeconds(dropoffDistanceMeters, current.speedKmh);
    const geometry = buildRouteGeometry(trip, current, 'dropoff');
    return {
      activeStopType: 'dropoff',
      activeStopLat: trip.destination_lat,
      activeStopLng: trip.destination_lng,
      distanceToActiveStopMeters: Math.round(dropoffDistanceMeters),
      proximityState: dropoffDistanceMeters <= approachRadiusMeters ? 'approaching_dropoff' : 'en_route_dropoff',
      etaSeconds: eta.seconds,
      etaSource: eta.source,
      ...geometry,
    };
  }

  const geometry = buildRouteGeometry(trip, current, 'dropoff');
  return {
    activeStopType: 'dropoff',
    activeStopLat: trip.destination_lat,
    activeStopLng: trip.destination_lng,
    distanceToActiveStopMeters: Math.round(dropoffDistanceMeters),
    proximityState: 'arrived_dropoff',
    etaSeconds: 0,
    etaSource: 'none',
    ...geometry,
  };
}

export function calculatePathDistanceMeters(points: DriverLocationPoint[]): number {
  if (points.length < 2) return 0;

  let total = 0;
  for (let i = 1; i < points.length; i++) {
    const prev = points[i - 1]!;
    const curr = points[i]!;
    total += haversineDistanceMeters(prev.lat, prev.lng, curr.lat, curr.lng);
  }

  return Math.round(total);
}

export function encodePolyline(points: Array<{ lat: number; lng: number }>): string {
  let lastLat = 0;
  let lastLng = 0;
  let encoded = '';

  const encodeValue = (value: number): string => {
    let shifted = value < 0 ? ~(value << 1) : value << 1;
    let output = '';
    while (shifted >= 0x20) {
      output += String.fromCharCode((0x20 | (shifted & 0x1f)) + 63);
      shifted >>= 5;
    }
    output += String.fromCharCode(shifted + 63);
    return output;
  };

  for (const point of points) {
    const lat = Math.round(point.lat * 1e5);
    const lng = Math.round(point.lng * 1e5);
    encoded += encodeValue(lat - lastLat);
    encoded += encodeValue(lng - lastLng);
    lastLat = lat;
    lastLng = lng;
  }

  return encoded;
}
