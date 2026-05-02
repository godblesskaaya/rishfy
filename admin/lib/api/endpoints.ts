import { apiClient } from './client';
import type {
  Booking,
  Driver,
  LatraTripRecord,
  ListResponse,
  PaginationParams,
  Payment,
  Route,
  User,
  Vehicle,
} from '@/types/api';

/**
 * Typed API facade. Organized by domain, each method returns a Promise
 * of the backend response. Designed to pair with TanStack Query.
 */

// =============================================================================
// Users
// =============================================================================

export const usersApi = {
  list: async (params: PaginationParams & { role?: string; search?: string }) => {
    const { data } = await apiClient.get<ListResponse<User>>('/users', {
      params,
    });
    return data;
  },

  get: async (userId: string) => {
    const { data } = await apiClient.get<User>(`/users/${userId}`);
    return data;
  },

  suspend: async (userId: string, reason: string) => {
    const { data } = await apiClient.post<{ success: boolean }>(
      `/users/${userId}/suspend`,
      { reason },
    );
    return data;
  },

  unsuspend: async (userId: string) => {
    const { data } = await apiClient.post<{ success: boolean }>(
      `/users/${userId}/unsuspend`,
    );
    return data;
  },
};

// =============================================================================
// Drivers & Vehicles
// =============================================================================

export const driversApi = {
  listPending: async (params: PaginationParams) => {
    const { data } = await apiClient.get<ListResponse<Driver>>(
      '/drivers/pending-verification',
      { params },
    );
    return data;
  },

  approve: async (userId: string) => {
    const { data } = await apiClient.post<{ success: boolean }>(
      `/drivers/${userId}/approve`,
    );
    return data;
  },

  reject: async (userId: string, reason: string) => {
    const { data } = await apiClient.post<{ success: boolean }>(
      `/drivers/${userId}/reject`,
      { reason },
    );
    return data;
  },
};

export const vehiclesApi = {
  list: async (params: PaginationParams & { latraVerified?: boolean }) => {
    const { data } = await apiClient.get<ListResponse<Vehicle>>('/vehicles', {
      params,
    });
    return data;
  },

  verify: async (vehicleId: string, latraLicense: string) => {
    const { data } = await apiClient.post<{ success: boolean }>(
      `/vehicles/${vehicleId}/verify`,
      { latra_license_number: latraLicense },
    );
    return data;
  },
};

// =============================================================================
// Routes
// =============================================================================

export const routesApi = {
  list: async (params: PaginationParams & { status?: string }) => {
    const { data } = await apiClient.get<ListResponse<Route>>('/routes', {
      params,
    });
    return data;
  },

  get: async (routeId: string) => {
    const { data } = await apiClient.get<Route>(`/routes/${routeId}`);
    return data;
  },
};

// =============================================================================
// Bookings
// =============================================================================

export const bookingsApi = {
  list: async (params: PaginationParams & { status?: string }) => {
    const { data } = await apiClient.get<ListResponse<Booking>>('/bookings', {
      params,
    });
    return data;
  },

  get: async (bookingId: string) => {
    const { data } = await apiClient.get<Booking>(`/bookings/${bookingId}`);
    return data;
  },

  forceCancel: async (bookingId: string, reason: string) => {
    const { data } = await apiClient.post<{ success: boolean }>(
      `/bookings/${bookingId}/admin-cancel`,
      { reason },
    );
    return data;
  },
};

// =============================================================================
// Payments
// =============================================================================

export const paymentsApi = {
  list: async (params: PaginationParams & { status?: string }) => {
    const { data } = await apiClient.get<ListResponse<Payment>>('/payments', {
      params,
    });
    return data;
  },

  get: async (paymentId: string) => {
    const { data } = await apiClient.get<Payment>(`/payments/${paymentId}`);
    return data;
  },

  refund: async (paymentId: string, amount: number, reason: string) => {
    const { data } = await apiClient.post<{ success: boolean }>(
      `/payments/${paymentId}/refund`,
      { amount, reason },
    );
    return data;
  },
};

// =============================================================================
// LATRA
// =============================================================================

export const latraApi = {
  getTrips: async (params: { startDate: string; endDate: string; cursor?: string }) => {
    const { data } = await apiClient.get<{
      trips: LatraTripRecord[];
      next_cursor?: string;
    }>('/latra/trips', { params });
    return data;
  },

  getComplianceStats: async () => {
    const { data } = await apiClient.get<{
      total_licensed_vehicles: number;
      total_trips_this_month: number;
      reporting_compliance_rate: number;
      last_report_submitted_at: string | null;
    }>('/latra/compliance-stats');
    return data;
  },
};

// =============================================================================
// Overview / Analytics
// =============================================================================

export const overviewApi = {
  getKpis: async () => {
    const res = await fetch('/api/admin/overview/kpis', { credentials: 'include' });
    if (!res.ok) throw new Error('KPIs fetch failed');
    return res.json() as Promise<{
      total_users: number;
      active_drivers: number;
      bookings_today: number;
      gross_revenue_tzs: number;
      delta_vs_last_week: { users: number; bookings: number; revenue: number };
    }>;
  },

  getBookingsTimeseries: async (days = 30) => {
    const res = await fetch(`/api/admin/overview/bookings-timeseries?days=${days}`, { credentials: 'include' });
    if (!res.ok) throw new Error('Timeseries fetch failed');
    return res.json() as Promise<Array<{ date: string; bookings: number; revenue: number }>>;
  },

  getTopRoutes: async (limit = 10) => {
    const res = await fetch(`/api/admin/overview/top-routes?limit=${limit}`, { credentials: 'include' });
    if (!res.ok) throw new Error('Top routes fetch failed');
    return res.json() as Promise<Array<{ origin: string; destination: string; bookings: number }>>;
  },
};
