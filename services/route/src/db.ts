import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import { config } from './config.js';

export const pgPool = new Pool({
  connectionString: config.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const db = new Kysely<any>({
  dialect: new PostgresDialect({ pool: pgPool }),
});
