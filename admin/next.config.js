/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,

  // Enable experimental App Router features we need
  experimental: {
    typedRoutes: true,
  },

  // Redirect root to dashboard
  async redirects() {
    return [
      {
        source: '/',
        destination: '/overview',
        permanent: false,
      },
    ];
  },

  // Rewrite /api/backend/* → Rishfy API gateway
  // This lets us proxy authenticated requests server-side so the JWT never
  // leaves the admin server.
  async rewrites() {
    const apiUrl = process.env.RISHFY_API_URL ?? 'http://localhost';
    return [
      {
        source: '/api/backend/:path*',
        destination: `${apiUrl}/api/v1/:path*`,
      },
    ];
  },

  // Image optimization — allow remote avatars + vehicle photos from our S3/MinIO
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '*.rishfy.tz' },
      { protocol: 'http', hostname: 'localhost' },
      { protocol: 'http', hostname: 'minio' },
    ],
  },

  // Headers — security defaults
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          {
            key: 'Permissions-Policy',
            value: 'camera=(), microphone=(), geolocation=()',
          },
        ],
      },
    ];
  },
};

module.exports = nextConfig;
