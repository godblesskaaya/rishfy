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
  createKafkaProducer,
  connectKafkaConsumer,
  connectKafkaProducer,
  startJsonConsumer,
} from './kafka.js';
import type { RatingSubmittedEvent } from './events/user.events.js';
import { TOPIC_RATING_SUBMITTED } from './events/user.events.js';
import { startUserRegisteredConsumer } from './consumers/user-registration.consumer.js';

async function main(): Promise<void> {
  const repo = new UserRepository(pgPool);
  const kafka = createKafkaClient({
    brokers: config.KAFKA_BROKERS.split(','),
    clientId: `${config.SERVICE_NAME}`,
    logger,
  });
  const producer = createKafkaProducer(kafka);
  await connectKafkaProducer(producer);

  const app = await buildApp({ userEventsProducer: producer });

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
  const ratingConsumer = createKafkaConsumer(kafka, { groupId: `${config.SERVICE_NAME}-ratings` });
  await connectKafkaConsumer(ratingConsumer);
  await startJsonConsumer<RatingSubmittedEvent>({
    consumer: ratingConsumer,
    topic: TOPIC_RATING_SUBMITTED,
    logger,
    onMessage: async ({ value }) => {
      const result = await repo.recordRating({
        rateeId: value.ratee_id,
        raterId: value.rater_id,
        bookingId: value.booking_id,
        score: value.score,
      });
      logger.info({ ratee_id: value.ratee_id, score: value.score, applied: result.applied }, 'Rating processed');
    },
  });
  logger.info(`Kafka consumer listening on topic: ${TOPIC_RATING_SUBMITTED}`);

  const registrationConsumer = await startUserRegisteredConsumer({
    kafka,
    repo,
    logger,
    groupId: `${config.SERVICE_NAME}-registrations`,
  });
  logger.info('Kafka consumer listening on topic: user.registered');

  const shutdown = async (signal: string): Promise<void> => {
    logger.info({ signal }, 'Shutting down...');
    try {
      await app.close();
      await ratingConsumer.disconnect();
      await registrationConsumer.disconnect();
      await producer.disconnect();
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
