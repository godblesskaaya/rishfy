import type { NextAuthOptions } from 'next-auth';
import CredentialsProvider from 'next-auth/providers/credentials';

import { apiClient } from '@/lib/api/client';

/**
 * Admin authentication via the Rishfy auth-service.
 *
 * Flow:
 *   1. Admin enters phone + password (admin accounts have passwords, unlike regular users)
 *   2. NextAuth calls auth-service /api/v1/auth/admin/login
 *   3. Receives JWT tokens + user profile
 *   4. Stores in encrypted NextAuth session (JWT strategy)
 *   5. Uses access token for subsequent backend calls
 *
 * Note: Regular mobile users authenticate via phone + OTP.
 * Admin accounts use phone + password for desktop/CLI convenience.
 */

interface AdminLoginResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  user: {
    user_id: string;
    first_name: string;
    last_name: string;
    phone_number: string;
    email?: string;
    role: 'admin' | 'support';
    permissions: string[];
  };
}

export const authOptions: NextAuthOptions = {
  session: {
    strategy: 'jwt',
    maxAge: 8 * 60 * 60, // 8 hours
  },

  pages: {
    signIn: '/login',
    error: '/login',
  },

  providers: [
    CredentialsProvider({
      name: 'credentials',
      credentials: {
        phoneNumber: { label: 'Phone', type: 'text' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        if (!credentials?.phoneNumber || !credentials.password) {
          return null;
        }

        try {
          const response = await apiClient.post<AdminLoginResponse>(
            '/api/v1/auth/admin/login',
            {
              phone_number: credentials.phoneNumber,
              password: credentials.password,
            },
          );

          const data = response.data;

          // Only admin/support roles can use this dashboard.
          if (!['admin', 'support'].includes(data.user.role)) {
            return null;
          }

          return {
            id: data.user.user_id,
            name: `${data.user.first_name} ${data.user.last_name}`,
            email: data.user.email ?? undefined,
            role: data.user.role,
            phoneNumber: data.user.phone_number,
            accessToken: data.access_token,
            refreshToken: data.refresh_token,
            accessTokenExpires: Date.now() + data.expires_in * 1000,
            permissions: data.user.permissions,
          };
        } catch (error) {
          console.error('Admin login failed:', error);
          return null;
        }
      },
    }),
  ],

  callbacks: {
    async jwt({ token, user }) {
      // Initial sign-in
      if (user) {
        return {
          ...token,
          accessToken: user.accessToken,
          refreshToken: user.refreshToken,
          accessTokenExpires: user.accessTokenExpires,
          role: user.role,
          permissions: user.permissions,
          phoneNumber: user.phoneNumber,
          userId: user.id,
        };
      }

      // Return previous token if still valid (>1 min remaining)
      if (
        token.accessTokenExpires &&
        Date.now() < (token.accessTokenExpires as number) - 60_000
      ) {
        return token;
      }

      // Access token expired — try refresh
      return refreshAccessToken(token);
    },

    async session({ session, token }) {
      session.user.id = token.userId as string;
      session.user.role = token.role as string;
      session.user.permissions = (token.permissions as string[]) ?? [];
      session.accessToken = token.accessToken as string;
      session.error = token.error as string | undefined;
      return session;
    },
  },
};

async function refreshAccessToken(token: Record<string, unknown>): Promise<Record<string, unknown>> {
  try {
    const response = await apiClient.post<{
      access_token: string;
      refresh_token: string;
      expires_in: number;
    }>('/api/v1/auth/refresh', {
      refresh_token: token.refreshToken,
    });

    return {
      ...token,
      accessToken: response.data.access_token,
      refreshToken: response.data.refresh_token ?? token.refreshToken,
      accessTokenExpires: Date.now() + response.data.expires_in * 1000,
    };
  } catch (error) {
    console.error('Token refresh failed:', error);
    return {
      ...token,
      error: 'RefreshAccessTokenError',
    };
  }
}
