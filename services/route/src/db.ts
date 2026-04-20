import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';

import { config } from './config.js';

// Service-specific schema type lives in src/types/db.ts — generated or hand-written.
// For now use `any` until schema is defined.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const db = new Kysely<any>({
  dialect: new PostgresDialect({
    pool: new Pool({
      connectionString: config.DATABASE_URL,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    }),
  }),
});
