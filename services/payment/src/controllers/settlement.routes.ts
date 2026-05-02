import type { FastifyInstance } from 'fastify';
import { SettlementRepository } from '../repositories/settlement.repository.js';
import { pgPool } from '../db.js';
import { logger } from '../logger.js';

const repo = new SettlementRepository(pgPool);

export async function settlementRoutes(app: FastifyInstance): Promise<void> {
  // GET /api/v1/drivers/:driverId/earnings
  app.get('/api/v1/drivers/:driverId/earnings', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { driverId } = req.params as { driverId: string };
    if (userId !== driverId) return reply.status(403).send({ error: 'FORBIDDEN' });

    const { from, to } = req.query as { from?: string; to?: string };
    const fromDate = from ? new Date(from) : new Date(Date.now() - 30 * 24 * 3600_000);
    const toDate = to ? new Date(to) : new Date();

    const summary = await repo.getDriverEarnings(driverId, fromDate, toDate);
    return reply.send(summary);
  });

  // POST /api/v1/drivers/:driverId/settlements
  app.post('/api/v1/drivers/:driverId/settlements', async (req, reply) => {
    const userId = req.headers['x-user-id'] as string;
    if (!userId) return reply.status(401).send({ error: 'UNAUTHORIZED' });
    const { driverId } = req.params as { driverId: string };
    if (userId !== driverId) return reply.status(403).send({ error: 'FORBIDDEN' });

    const body = req.body as {
      periodStart: string;
      periodEnd: string;
      payoutMethod: string;
      payoutPhone: string;
      bookingIds: Array<{ bookingId: string; driverEarningsTzs: number }>;
    };

    const totalAmountTzs = body.bookingIds.reduce((sum, b) => sum + b.driverEarningsTzs, 0);
    const platformFeeTzs = Math.round(totalAmountTzs * 0.15);
    const netAmountTzs = totalAmountTzs - platformFeeTzs;

    try {
      const settlement = await repo.create({
        driverUserId: driverId,
        periodStart: new Date(body.periodStart),
        periodEnd: new Date(body.periodEnd),
        totalAmountTzs,
        platformFeeTzs,
        netAmountTzs,
        bookingCount: body.bookingIds.length,
        payoutMethod: body.payoutMethod,
        payoutPhone: body.payoutPhone,
        bookingIds: body.bookingIds,
      });
      return reply.status(201).send(settlement);
    } catch (err) {
      logger.error({ err }, 'POST /drivers/:driverId/settlements failed');
      return reply.status(500).send({ error: 'INTERNAL_ERROR' });
    }
  });
}
