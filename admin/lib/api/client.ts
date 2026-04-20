import axios, { type AxiosInstance, type InternalAxiosRequestConfig } from 'axios';
import { getSession, signOut } from 'next-auth/react';

/**
 * Base API URL.
 *
 * Server-side: uses RISHFY_API_URL directly (talks to backend gateway).
 * Client-side: uses /api/backend/* which Next.js rewrites to the gateway.
 */
const baseURL =
  typeof window === 'undefined'
    ? process.env.RISHFY_API_URL ?? 'http://localhost'
    : '/api/backend';

/**
 * Client-side API client.
 * Auto-injects the NextAuth access token on every request.
 */
export const apiClient: AxiosInstance = axios.create({
  baseURL,
  timeout: 30_000,
  headers: {
    'Content-Type': 'application/json',
    'X-Client': 'rishfy-admin',
  },
});

// Request interceptor — inject auth token
apiClient.interceptors.request.use(async (config: InternalAxiosRequestConfig) => {
  // Server-side: inject admin service token from env
  if (typeof window === 'undefined') {
    const serviceToken = process.env.RISHFY_ADMIN_SERVICE_TOKEN;
    if (serviceToken) {
      config.headers.Authorization = `Bearer ${serviceToken}`;
    }
    return config;
  }

  // Client-side: pull from NextAuth session
  const session = await getSession();
  if (session?.accessToken) {
    config.headers.Authorization = `Bearer ${session.accessToken}`;
  }
  return config;
});

// Response interceptor — handle auth errors
apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    // 401 — session expired or token refresh failed
    if (error.response?.status === 401 && typeof window !== 'undefined') {
      const session = await getSession();
      if (session?.error === 'RefreshAccessTokenError') {
        await signOut({ callbackUrl: '/login' });
      }
    }
    return Promise.reject(error);
  },
);
