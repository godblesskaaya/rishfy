import { config } from '../config.js';

interface DirectionsResult {
  polyline: string;
  distance_meters: number;
  duration_seconds: number;
}

interface LatLng {
  lat: number;
  lng: number;
}

const DIRECTIONS_URL = 'https://maps.googleapis.com/maps/api/directions/json';

export async function getDirections(origin: LatLng, destination: LatLng): Promise<DirectionsResult | null> {
  const params = new URLSearchParams({
    origin: `${origin.lat},${origin.lng}`,
    destination: `${destination.lat},${destination.lng}`,
    mode: 'driving',
    key: config.GOOGLE_MAPS_API_KEY,
  });

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
  const leg = route.legs[0];
  return {
    polyline: route.overview_polyline.points,
    distance_meters: leg?.distance.value ?? 0,
    duration_seconds: leg?.duration.value ?? 0,
  };
}
