import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth/options';
import { Pool } from 'pg';

const pool = new Pool({ connectionString: process.env.USER_DATABASE_URL ?? process.env.DATABASE_URL });

export async function GET(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const days = parseInt(req.nextUrl.searchParams.get('days') ?? '30', 10);
  const fromDate = new Date(Date.now() - days * 24 * 3600_000);

  try {
    const { rows } = await pool.query<{ date: string; bookings: string; revenue: string }>(
      `SELECT
         TO_CHAR(created_at::date, 'YYYY-MM-DD') as date,
         COUNT(*)::int as bookings,
         COALESCE(SUM(total_price),0)::bigint as revenue
       FROM bookings
       WHERE created_at >= $1
       GROUP BY 1
       ORDER BY 1`,
      [fromDate],
    );

    return NextResponse.json(
      rows.map((r) => ({
        date: r.date,
        bookings: parseInt(r.bookings, 10),
        revenue: parseInt(r.revenue, 10),
      })),
    );
  } catch (err) {
    console.error('Timeseries query failed:', err);
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 });
  }
}
