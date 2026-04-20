import { withAuth } from 'next-auth/middleware';
import { NextResponse } from 'next/server';

export default withAuth(
  function middleware(req) {
    // Already authenticated — allow
    return NextResponse.next();
  },
  {
    callbacks: {
      authorized: ({ token, req }) => {
        // Login page is public
        if (req.nextUrl.pathname.startsWith('/login')) return true;

        // Everything else requires a valid token
        if (!token) return false;

        // Check for refresh token errors
        if (token.error === 'RefreshAccessTokenError') return false;

        // Only admin/support roles allowed
        const allowedRoles = ['admin', 'support'];
        return allowedRoles.includes(token.role as string);
      },
    },
    pages: {
      signIn: '/login',
    },
  },
);

export const config = {
  matcher: [
    /*
     * Match all request paths EXCEPT:
     *   - _next/static (static files)
     *   - _next/image (image optimization)
     *   - favicon, icons
     *   - api/auth (NextAuth endpoints)
     *   - api/health (health check)
     *   - login (public)
     */
    '/((?!_next/static|_next/image|favicon.ico|icons|api/auth|api/health|login).*)',
  ],
};
