import type { DefaultSession } from 'next-auth';

declare module 'next-auth' {
  interface Session {
    user: {
      id: string;
      role: string;
      permissions: string[];
    } & DefaultSession['user'];
    accessToken: string;
    error?: string;
  }

  interface User {
    id: string;
    accessToken: string;
    refreshToken: string;
    accessTokenExpires: number;
    role: string;
    phoneNumber: string;
    permissions: string[];
  }
}

declare module 'next-auth/jwt' {
  interface JWT {
    accessToken?: string;
    refreshToken?: string;
    accessTokenExpires?: number;
    role?: string;
    permissions?: string[];
    phoneNumber?: string;
    userId?: string;
    error?: string;
  }
}
