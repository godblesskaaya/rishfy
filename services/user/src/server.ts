import * as grpc from '@grpc/grpc-js';
import { buildApp } from './app.js';
import { config } from './config.js';
import { pgPool } from './db.js';
import { logger } from './logger.js';
import { UserRepository } from './repositories/user.repository.js';
import { createUserGrpcServer } from './grpc/user.server.js';
import {
  createKafkaClient,
  createKafkaConsumer,
  connectKafkaConsumer,
  startJsonConsumer,
} from './kafka.js';
import type { RatingSubmittedEvent } from './events/user.events.js';
import { TOPIC_RATING_SUBMITTED } from './events/user.events.js';

async function main(): Promise<void> {
  const repo = new UserRepository(pgPool);
  const app = await buildApp();

  // HTTP server
  await app.listen({ port: config.HTTP_PORT, host: '0.0.0.0' });
  logger.info(`HTTP server listening on :${config.HTTP_PORT}`);

  // gRPC server
  const grpcServer = createUserGrpcServer(repo);
  await new Promise<void>((resolve, reject) => {
    grpcServer.bindAsync(
      `0.0.0.0:${config.GRPC_PORT}`,
      grpc.ServerCredentials.createInsecure(),
      (err) => { if (err) reject(err); else resolve(); },
    );
  });
  logger.info(`gRPC server listening on :${config.GRPC_PORT}`);

  // Kafka consumer — rating.submitted → update user average rating
  const kafka = createKafkaClient({
    brokers: config.KAFKA_BROKERS.split(','),
    clientId: `${config.SERVICE_NAME}-consumer`,
    logger,
  });
  const consumer = createKafkaConsumer(kafka, { groupId: `${config.SERVICE_NAME}-ratings` });
  await connectKafkaConsumer(consumer);
  await startJsonConsumer<RatingSubmittedEvent>({
    consumer,
    topic: TOPIC_RATING_SUBMITTED,
    logger,
    onMessage: async ({ value }) => {
      await repo.updateRating(value.ratee_id, value.score);
      logger.info({ ratee_id: value.ratee_id, score: value.score }, 'Rating applied');
    },
  });
  logger.info(`Kafka consumer listening on topic: ${TOPIC_RATING_SUBMITTED}`);

  const shutdown = async (signal: string): Promise<void> => {
    logger.info({ signal }, 'Shutting down...');
    try {
      await app.close();
      grpcServer.forceShutdown();
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
