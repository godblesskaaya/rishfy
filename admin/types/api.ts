/**
 * Shared API types.
 * Mirror the backend DTOs. Keep in sync with OpenAPI spec in docs/API_CONTRACTS.md.
 */

export interface PaginationParams {
  page?: number;
  page_size?: number;
  sort_by?: string;
  sort_order?: 'asc' | 'desc';
}

export interface ListResponse<T> {
  items: T[];
  pagination: {
    page: number;
    page_size: number;
    total_count: number;
    total_pages: number;
    has_next: boolean;
    has_previous: boolean;
  };
}

// =============================================================================
// User
// =============================================================================

export type UserRole = 'passenger' | 'driver' | 'admin' | 'support';
export type UserStatus = 'active' | 'suspended' | 'deleted';

export interface User {
  user_id: string;
  phone_number: string;
  email: string | null;
  first_name: string;
  last_name: string;
  profile_picture_url: string | null;
  role: UserRole;
  status: UserStatus;
  is_verified: boolean;
  rating_average: number;
  rating_count: number;
  language: 'en' | 'sw';
  created_at: string;
  last_login_at: string | null;
}

// =============================================================================
// Driver (extends User)
// =============================================================================

export interface Driver extends User {
  license_number: string;
  license_verified: boolean;
  license_expiry: string | null;
  total_trips: number;
  accepting_routes: boolean;
  vehicles: Vehicle[];
}

// =============================================================================
// Vehicle
// =============================================================================

export interface Vehicle {
  vehicle_id: string;
  owner_user_id: string;
  owner_name?: string;
  registration_number: string;
  make: string;
  model: string;
  year: number;
  color: string;
  seat_capacity: number;
  latra_verified: boolean;
  latra_license_number: string | null;
  latra_expiry: string | null;
  insurance_valid: boolean;
  insurance_expiry: string | null;
  photo_urls: string[];
  created_at: string;
}

// =============================================================================
// Route
// =============================================================================

export type RouteStatus =
  | 'draft'
  | 'posted'
  | 'full'
  | 'in_progress'
  | 'completed'
  | 'cancelled';

export interface Coordinates {
  latitude: number;
  longitude: number;
}

export interface RouteLocation {
  coordinates: Coordinates;
  formatted_address: string;
  place_id: string | null;
  city: string;
  region: string;
}

export interface Route {
  route_id: string;
  driver_user_id: string;
  driver_name?: string;
  vehicle_id: string;
  origin: RouteLocation;
  destination: RouteLocation;
  departure_time: string;
  estimated_arrival: string;
  total_seats: number;
  available_seats: number;
  price_per_seat: number;
  status: RouteStatus;
  polyline: string;
  distance_meters: number;
  duration_seconds: number;
  created_at: string;
}

// =============================================================================
// Booking
// =============================================================================

export type BookingStatus =
  | 'pending'
  | 'confirmed'
  | 'cancelled'
  | 'completed'
  | 'no_show';

export type TripStatus =
  | 'scheduled'
  | 'started'
  | 'in_progress'
  | 'completed'
  | 'cancelled';

export interface Booking {
  booking_id: string;
  confirmation_code: string;
  route_id: string;
  passenger_user_id: string;
  passenger_name?: string;
  driver_user_id: string;
  driver_name?: string;
  seat_count: number;
  total_amount: number;
  driver_earnings: number;
  platform_fee: number;
  status: BookingStatus;
  trip_status: TripStatus;
  pickup_address: string;
  dropoff_address: string;
  created_at: string;
  confirmed_at: string | null;
  cancelled_at: string | null;
  trip_started_at: string | null;
  trip_completed_at: string | null;
  cancellation_reason: string | null;
  passenger_rating: number | null;
  driver_rating: number | null;
}

// =============================================================================
// Payment
// =============================================================================

export type PaymentStatus =
  | 'initiated'
  | 'processing'
  | 'completed'
  | 'failed'
  | 'refunded';

export type PaymentMethod = 'mpesa' | 'tigopesa' | 'airtel_money' | 'cash';

export interface Payment {
  payment_id: string;
  booking_id: string;
  user_id: string;
  user_name?: string;
  amount: number;
  method: PaymentMethod;
  status: PaymentStatus;
  provider_reference: string | null;
  internal_reference: string;
  payer_phone: string;
  failure_code: string | null;
  failure_message: string | null;
  initiated_at: string;
  completed_at: string | null;
  refunded_amount: number;
}

// =============================================================================
// LATRA
// =============================================================================

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
}
