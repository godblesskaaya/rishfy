# Rishfy Admin Dashboard

> **Owner:** Godbless Kaaya (admin lead) + team contributions
> **Stack:** Next.js 14 · React 18 · TypeScript · Tailwind · shadcn/ui · TanStack Query · NextAuth.js

---

## Quick Start

```bash
cd admin

# Install dependencies
npm install

# Set up environment
cp .env.example .env.local
# Edit .env.local — at minimum set NEXTAUTH_SECRET

# Start dev server
npm run dev
# → http://localhost:3000
```

**Prerequisites:**

- Node.js 20+
- Running Rishfy backend (via `./scripts/dev.sh up` in repo root)
- `NEXTAUTH_SECRET` set (generate: `openssl rand -hex 32`)

---

## Environment Variables

Required in `.env.local`:

```bash
NEXTAUTH_URL=http://localhost:3000
NEXTAUTH_SECRET=<32-byte-hex>
RISHFY_API_URL=http://localhost
```

Optional:

```bash
# Admin service token for server-side backend calls
RISHFY_ADMIN_SERVICE_TOKEN=

# For route visualizations on the admin side
NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=

NEXT_PUBLIC_APP_ENV=development
```

---

## Architecture

```
admin/
├── app/                         Next.js 14 App Router
│   ├── (auth)/login/            Public login page (grouped)
│   ├── (dashboard)/             Authenticated area (grouped)
│   │   ├── layout.tsx           Sidebar + topbar shell
│   │   ├── overview/            KPI dashboard
│   │   ├── users/               User management
│   │   ├── drivers/             Driver verification
│   │   ├── vehicles/            Vehicle + LATRA status
│   │   ├── routes/              All routes posted
│   │   ├── bookings/            Booking oversight
│   │   ├── payments/            Transactions + refunds
│   │   ├── latra/               Compliance reports
│   │   └── settings/            Config + profile
│   └── api/                     Route handlers
│       ├── auth/[...nextauth]/  NextAuth.js endpoints
│       └── health/              Health check
│
├── components/
│   ├── ui/                      shadcn/ui primitives (button, card, table, etc.)
│   ├── charts/                  Recharts wrappers
│   ├── data-table/              TanStack Table with pagination/sorting
│   ├── layout/                  Sidebar, topbar, page header
│   ├── kpi-card.tsx             Dashboard metric card
│   ├── status-badge.tsx         Consistent status display
│   └── providers.tsx            React Query + NextAuth providers
│
├── lib/
│   ├── api/                     Typed API client + endpoint functions
│   ├── auth/                    NextAuth options
│   └── utils/                   Formatters (TZS, dates, phone masking)
│
├── types/
│   ├── api.ts                   Backend DTO types (mirrors OpenAPI)
│   └── next-auth.d.ts           NextAuth session augmentation
│
└── middleware.ts                Route protection + role checking
```

### Authentication Flow

1. Admin hits any dashboard route → middleware checks session
2. No session → redirect to `/login`
3. Submit credentials → NextAuth calls `auth-service` admin login endpoint
4. Receives JWT + refresh token → stored in encrypted NextAuth session
5. All backend calls via `lib/api/client.ts` auto-inject the access token
6. Token expiring soon? → Automatic refresh via NextAuth jwt callback

**Why NextAuth + custom backend instead of direct backend login?**

- Session is encrypted and HttpOnly — access tokens never exposed to client JS
- Refresh handling is centralized
- Works with middleware for server-side route protection
- Easy to add SSO providers (Google, Microsoft) later

### Server vs Client Components

- **Server components** (default): data fetching, auth checks, layouts
- **Client components** (`'use client'`): interactivity, forms, TanStack Query

The dashboard layout (`app/(dashboard)/layout.tsx`) is a server component — it checks the session with `getServerSession` before rendering, so unauthorized users never see the UI.

---

## Data Fetching Patterns

We use **TanStack Query** for all client-side data.

```tsx
import { useQuery } from '@tanstack/react-query';
import { usersApi } from '@/lib/api/endpoints';

function UsersList() {
  const { data, isLoading } = useQuery({
    queryKey: ['users', { page: 1 }],
    queryFn: () => usersApi.list({ page: 1, page_size: 20 }),
  });
  // ...
}
```

**Query key convention:** `[<domain>, <filters...>]` — makes cache invalidation easy.

**Mutations:**

```tsx
const mutation = useMutation({
  mutationFn: (id: string) => driversApi.approve(id),
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['drivers'] });
    toast.success('Driver approved');
  },
});
```

---

## Adding a New Page

1. Create route in `app/(dashboard)/<slug>/page.tsx`
2. Add navigation entry in `components/layout/sidebar.tsx`
3. Add types to `types/api.ts` if new DTOs are needed
4. Add API functions to `lib/api/endpoints.ts`
5. Use existing components: `PageHeader`, `DataTable`, `KpiCard`, `StatusBadge`

---

## Theming

Tailwind CSS variables drive the theme. Edit `app/globals.css` to change:

- Primary color (teal)
- Accent color (amber)
- Border radius (`--radius`)
- Light/dark mode variants

---

## Testing

```bash
npm run test                  # Unit tests (Vitest)
npm run test:e2e              # E2E tests (Playwright)
```

**Test what matters:**

- Auth flow (login success, failure, refresh)
- Data table sorting/filtering
- LATRA export correctness (critical for compliance)
- Form validation

Mock the API with MSW (Mock Service Worker) — set up once, used in both unit and E2E.

---

## Build & Deploy

### Docker

```bash
docker build -t rishfy/admin:latest .
docker run -p 3000:3000 \
  -e NEXTAUTH_SECRET=... \
  -e NEXTAUTH_URL=https://admin.rishfy.tz \
  -e RISHFY_API_URL=https://api.rishfy.tz \
  rishfy/admin:latest
```

### Production considerations

- **Standalone output**: enable `output: 'standalone'` in `next.config.js` for smaller Docker images
- **CDN**: serve static assets via CDN (Cloudflare, CloudFront)
- **Session storage**: NextAuth JWT sessions require no server storage — scales horizontally by default
- **Rate limiting**: handled at NGINX gateway (see `infrastructure/nginx.conf`)

---

## LATRA Page Importance

The `/latra` page is **critical for regulatory compliance**. It:

1. Shows live compliance stats (licensed vehicles, trip count, reporting rate)
2. Lets the supervisor export trips in the exact format LATRA's API expects
3. Serves as the backup if the automated reporting API fails

**Do not break the LATRA CSV export.** If you change the format, update `docs/LATRA_COMPLIANCE.md` and notify the team.

---

## Common Commands

```bash
npm run dev                # Start dev server
npm run build              # Production build
npm run lint               # Lint all files
npm run lint:fix           # Auto-fix lint issues
npm run typecheck          # TypeScript check
npm run format             # Prettier
npm run test               # Run tests
```

---

## Troubleshooting

**Can't log in**
- Check `RISHFY_API_URL` points to a running backend
- Verify the admin user exists in `auth_db.users` with `role='admin'`
- Check browser console for specific errors

**CORS errors**
- Admin calls go via `/api/backend/*` rewrite — no CORS needed
- If adding direct calls, update `next.config.js` rewrites

**Session expires immediately**
- Verify `NEXTAUTH_SECRET` is set and matches between deploys
- Check `NEXTAUTH_URL` matches your actual URL

**"Module not found" errors**
- Run `npm install` to refresh dependencies
- Check `tsconfig.json` path aliases match your import patterns (all use `@/*`)

---

## Next Steps

Features to build post-scaffolding:

- [ ] User detail page with full profile + history
- [ ] Driver detail with verification workflow (KYC documents)
- [ ] Route detail with map preview
- [ ] Booking detail with saga trace visualization
- [ ] Payment refund modal with amount calculation
- [ ] Bulk operations (CSV import/export)
- [ ] Real-time active trips map (WebSocket to location-service)
- [ ] Admin activity audit log
- [ ] Notification composer (send broadcasts to users)

Each page today renders a skeleton with live data from the backend. Extend iteratively — the foundation handles auth, data fetching, tables, and consistent styling.
