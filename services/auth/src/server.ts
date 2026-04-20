import { buildApp } from './app.js';
import { config } from './config.js';
import { logger } from './logger.js';
// import { startGrpcServer } from './grpc/server.js';

async function main(): Promise<void> {
  const app = await buildApp();

  // Start HTTP server
  try {
    await app.listen({ port: config.HTTP_PORT, host: '0.0.0.0' });
    logger.info(`HTTP server listening on :${config.HTTP_PORT}`);
  } catch (err) {
    logger.error({ err }, 'Failed to start HTTP server');
    process.exit(1);
  }

  // Start gRPC server
  // await startGrpcServer(config.GRPC_PORT);
  logger.info(`gRPC server will listen on :${config.GRPC_PORT} (not yet wired)`);

  // Graceful shutdown
  const shutdown = async (signal: string): Promise<void> => {
    logger.info({ signal }, 'Shutting down...');
    try {
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
