import { config } from '../config.js';

export interface LatLng {
  lat: number;
  lng: number;
}

interface DirectionsResult {
  polyline: string;
  distance_meters: number;
  duration_seconds: number;
}

const DIRECTIONS_URL = 'https://maps.googleapis.com/maps/api/directions/json';
const GEOCODE_URL    = 'https://maps.googleapis.com/maps/api/geocode/json';

export async function getDirections(
  origin: LatLng,
  destination: LatLng,
  waypoints?: LatLng[],
): Promise<DirectionsResult | null> {
  const params = new URLSearchParams({
    origin: `${origin.lat},${origin.lng}`,
    destination: `${destination.lat},${destination.lng}`,
    mode: 'driving',
    key: config.GOOGLE_MAPS_API_KEY,
  });

  if (waypoints && waypoints.length > 0) {
    params.set('waypoints', waypoints.map(w => `via:${w.lat},${w.lng}`).join('|'));
  }

  const res = await fetch(`${DIRECTIONS_URL}?${params}`);
  if (!res.ok) return null;

  const data = await res.json() as {
    status: string;
    routes: Array<{
      overview_polyline: { points: string };
      legs: Array<{ distance: { value: number }; duration: { value: number } }>;
    }>;
  };

  if (data.status !== 'OK' || !data.routes[0]) return null;

  const route = data.routes[0];
  const totalDistance = route.legs.reduce((sum, l) => sum + l.distance.value, 0);
  const totalDuration = route.legs.reduce((sum, l) => sum + l.duration.value, 0);

  return {
    polyline: route.overview_polyline.points,
    distance_meters: totalDistance,
    duration_seconds: totalDuration,
  };
}

export async function getWalkingDistance(
  origin: LatLng,
  destination: LatLng,
): Promise<{ distance_meters: number; duration_seconds: number } | null> {
  const params = new URLSearchParams({
    origin: `${origin.lat},${origin.lng}`,
    destination: `${destination.lat},${destination.lng}`,
    mode: 'walking',
    key: config.GOOGLE_MAPS_API_KEY,
  });

  const res = await fetch(`${DIRECTIONS_URL}?${params}`);
  if (!res.ok) return null;

  const data = await res.json() as {
    status: string;
    routes: Array<{
      legs: Array<{ distance: { value: number }; duration: { value: number } }>;
    }>;
  };

  if (data.status !== 'OK' || !data.routes[0]) return null;

  const leg = data.routes[0].legs[0];
  if (!leg) return null;

  return {
    distance_meters: leg.distance.value,
    duration_seconds: leg.duration.value,
  };
}

export async function reverseGeocode(lat: number, lng: number): Promise<string | null> {
  const params = new URLSearchParams({
    latlng: `${lat},${lng}`,
    key: config.GOOGLE_MAPS_API_KEY,
  });

  const res = await fetch(`${GEOCODE_URL}?${params}`);
  if (!res.ok) return null;

  const data = await res.json() as {
    status: string;
    results: Array<{ formatted_address: string }>;
  };

  if (data.status !== 'OK' || !data.results[0]) return null;

  return data.results[0].formatted_address;
}
