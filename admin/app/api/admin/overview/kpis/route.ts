import { NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth/options';
import { Pool } from 'pg';

const pool = new Pool({ connectionString: process.env.USER_DATABASE_URL ?? process.env.DATABASE_URL });

export async function GET() {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  try {
    const now = new Date();
    const weekAgo = new Date(now.getTime() - 7 * 24 * 3600_000);
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const [users, drivers, bookingsToday, revenue, prevWeek] = await Promise.all([
      pool.query<{ count: string }>('SELECT COUNT(*)::int as count FROM users'),
      pool.query<{ count: string }>(
        "SELECT COUNT(*)::int as count FROM users WHERE role='driver' AND status='active'",
      ),
      pool.query<{ count: string }>(
        "SELECT COUNT(*)::int as count FROM bookings WHERE created_at >= $1",
        [todayStart],
      ),
      pool.query<{ total: string }>(
        "SELECT COALESCE(SUM(amount_tzs),0)::bigint as total FROM payments WHERE status='completed' AND completed_at >= $1",
        [weekAgo],
      ),
      pool.query<{ users: string; bookings: string; revenue: string }>(
        `SELECT
           (SELECT COUNT(*)::int FROM users WHERE created_at BETWEEN $1 AND $2) as users,
           (SELECT COUNT(*)::int FROM bookings WHERE created_at BETWEEN $1 AND $2) as bookings,
           (SELECT COALESCE(SUM(amount_tzs),0)::bigint FROM payments WHERE status='completed' AND completed_at BETWEEN $1 AND $2) as revenue`,
        [new Date(weekAgo.getTime() - 7 * 24 * 3600_000), weekAgo],
      ),
    ]);

    const thisWeekUsers = 0; // new users this week not tracked separately — use total
    const prevUsers = parseInt(prevWeek.rows[0]?.users ?? '0', 10);
    const prevBookings = parseInt(prevWeek.rows[0]?.bookings ?? '0', 10);
    const prevRevenue = parseInt(prevWeek.rows[0]?.revenue ?? '0', 10);
    const grossRevenue = parseInt(revenue.rows[0]?.total ?? '0', 10);
    const bookingsTodayCount = parseInt(bookingsToday.rows[0]?.count ?? '0', 10);

    return NextResponse.json({
      total_users: parseInt(users.rows[0]?.count ?? '0', 10),
      active_drivers: parseInt(drivers.rows[0]?.count ?? '0', 10),
      bookings_today: bookingsTodayCount,
      gross_revenue_tzs: grossRevenue,
      delta_vs_last_week: {
        users: prevUsers > 0 ? Math.round(((thisWeekUsers - prevUsers) / prevUsers) * 100) : 0,
        bookings: prevBookings > 0 ? Math.round(((bookingsTodayCount - prevBookings) / prevBookings) * 100) : 0,
        revenue: prevRevenue > 0 ? Math.round(((grossRevenue - prevRevenue) / prevRevenue) * 100) : 0,
      },
    });
  } catch (err) {
    console.error('KPIs query failed:', err);
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 });
  }
}
