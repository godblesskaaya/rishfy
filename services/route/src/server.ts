import { buildApp } from './app.js';
import { config } from './config.js';
import { pgPool } from './db.js';
import { logger } from './logger.js';
import { startGrpcServer } from './grpc/route.server.js';
import {
  createKafkaClient,
  createKafkaProducer,
  connectKafkaProducer,
} from './kafka.js';

async function main(): Promise<void> {
  const kafka = createKafkaClient({
    brokers: config.KAFKA_BROKERS.split(','),
    clientId: config.SERVICE_NAME,
    logger,
  });
  const producer = createKafkaProducer(kafka);
  await connectKafkaProducer(producer);

  const app = await buildApp({ routeEventsProducer: producer });

  await app.listen({ port: config.HTTP_PORT, host: '0.0.0.0' });
  logger.info(`HTTP server listening on :${config.HTTP_PORT}`);

  startGrpcServer();

  const shutdown = async (signal: string): Promise<void> => {
    logger.info({ signal }, 'Shutting down...');
    try {
      await app.close();
      await producer.disconnect();
      await pgPool.end();
      process.exit(0);
    } catch (err) {
      logger.error({ err }, 'Error during shutdown');
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('unhandledRejection', (reason) => { logger.error({ reason }, 'Unhandled rejection'); });
  process.on('uncaughtException', (err) => { logger.fatal({ err }, 'Uncaught exception'); process.exit(1); });
}

main().catch((err: unknown) => {
  console.error('Fatal startup error:', err);
  process.exit(1);
});
