import type { Pool } from 'pg';
import { logger } from '../logger.js';

const INTERVAL_MS = 60_000; // 1 minute

export function startRouteExpiryWorker(pool: Pool): NodeJS.Timeout {
  const tick = async () => {
    try {
      const { rowCount } = await pool.query(
        `UPDATE routes
         SET status = 'departed', updated_at = now()
         WHERE status = 'active'
           AND departure_time + (flexibility_minutes * INTERVAL '1 minute') < now()`,
      );
      if (rowCount && rowCount > 0) {
        logger.info({ count: rowCount }, 'Marked routes as departed');
      }
    } catch (err) {
      logger.error({ err }, 'Route expiry worker error');
    }
  };

  void tick(); // run immediately on startup
  return setInterval(() => void tick(), INTERVAL_MS);
}
