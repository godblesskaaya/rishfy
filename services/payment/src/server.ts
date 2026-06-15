import { buildApp } from './app.js';
import { config } from './config.js';
import { logger } from './logger.js';
import { startGrpcServer } from './grpc/payment.server.js';
import { startPaymentConsumers } from './consumers/payment.consumers.js';
import { PaymentRepository } from './repositories/payment.repository.js';
import { pgPool } from './db.js';
import { startPaymentOutboxDispatcher } from './events/payment.events.js';

async function main(): Promise<void> {
  const app = await buildApp();
  let outboxDispatcher: NodeJS.Timeout | null = null;

  // Start HTTP server
  try {
    await app.listen({ port: config.HTTP_PORT, host: '0.0.0.0' });
    logger.info(`HTTP server listening on :${config.HTTP_PORT}`);
  } catch (err) {
    logger.error({ err }, 'Failed to start HTTP server');
    process.exit(1);
  }

  // Start gRPC server
  startGrpcServer();

  // Start Kafka consumers
  await startPaymentConsumers();

  // Start outbox dispatcher after Kafka is available.
  outboxDispatcher = startPaymentOutboxDispatcher(new PaymentRepository(pgPool));

  // Graceful shutdown
  const shutdown = async (signal: string): Promise<void> => {
    logger.info({ signal }, 'Shutting down...');
    try {
      if (outboxDispatcher) clearInterval(outboxDispatcher);
      await app.close();
      // TODO: close DB pool, Redis, Kafka
      process.exit(0);
    } catch (err) {
      logger.error({ err }, 'Error during shutdown');
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('unhandledRejection', (reason) => {
    logger.error({ reason }, 'Unhandled rejection');
  });
  process.on('uncaughtException', (err) => {
    logger.fatal({ err }, 'Uncaught exception');
    process.exit(1);
  });
}

main().catch((err: unknown) => {
  // eslint-disable-next-line no-console
  console.error('Fatal startup error:', err);
  process.exit(1);
});
