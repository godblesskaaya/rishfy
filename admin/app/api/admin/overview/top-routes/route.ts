import { NextRequest, NextResponse } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth/options';
import { Pool } from 'pg';

const pool = new Pool({ connectionString: process.env.USER_DATABASE_URL ?? process.env.DATABASE_URL });

export async function GET(req: NextRequest) {
  const session = await getServerSession(authOptions);
  if (!session) return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const limit = parseInt(req.nextUrl.searchParams.get('limit') ?? '10', 10);

  try {
    const { rows } = await pool.query<{ origin: string; destination: string; bookings: string }>(
      `SELECT
         r.origin_name as origin,
         r.destination_name as destination,
         COUNT(b.id)::int as bookings
       FROM routes r
       JOIN bookings b ON b.route_id = r.id
       WHERE b.created_at >= NOW() - INTERVAL '30 days'
       GROUP BY r.id, r.origin_name, r.destination_name
       ORDER BY bookings DESC
       LIMIT $1`,
      [limit],
    );

    return NextResponse.json(
      rows.map((r) => ({
        origin: r.origin,
        destination: r.destination,
        bookings: parseInt(r.bookings, 10),
      })),
    );
  } catch (err) {
    console.error('Top routes query failed:', err);
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 });
  }
}
