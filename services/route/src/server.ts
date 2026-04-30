import { buildApp } from './app.js';
import { config } from './config.js';
import { pgPool } from './db.js';
import { logger } from './logger.js';

async function main(): Promise<void> {
  const app = await buildApp();

  await app.listen({ port: config.HTTP_PORT, host: '0.0.0.0' });
  logger.info(`HTTP server listening on :${config.HTTP_PORT}`);

  const shutdown = async (signal: string): Promise<void> => {
    logger.info({ signal }, 'Shutting down...');
    try {
      await app.close();
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
