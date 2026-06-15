import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { Pool } from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

const __dirname = dirname(fileURLToPath(import.meta.url));
const serviceDir = resolve(__dirname, '../..');

process.env['TESTCONTAINERS_RYUK_DISABLED'] = process.env['TESTCONTAINERS_RYUK_DISABLED'] ?? 'true';

describe('payment ledger migrations', () => {
  let container: StartedPostgreSqlContainer;
  let pool: Pool;

  beforeAll(async () => {
    container = await new PostgreSqlContainer('postgres:16-alpine').start();
    const databaseUrl = container.getConnectionUri();
    execFileSync('npx', ['node-pg-migrate', 'up', '--migrations-dir', 'migrations'], {
      cwd: serviceDir,
      env: { ...process.env, DATABASE_URL: databaseUrl },
      stdio: 'pipe',
    });
    pool = new Pool({ connectionString: databaseUrl });
  }, 120000);

  afterAll(async () => {
    await pool?.end();
    await container?.stop();
  }, 30000);

  it('creates the ledger, payout, reconciliation, and outbox tables', async () => {
    const { rows } = await pool.query<{ table_name: string }>(
      `SELECT table_name
       FROM information_schema.tables
       WHERE table_schema='public'
         AND table_name = ANY($1)
       ORDER BY table_name`,
      [[
        'ledger_accounts',
        'ledger_journals',
        'ledger_entries',
        'payouts',
        'payout_holds',
        'payout_hold_requests',
        'provider_reconciliation_records',
        'payment_event_outbox',
      ]],
    );

    expect(rows.map((row) => row.table_name)).toEqual([
      'ledger_accounts',
      'ledger_entries',
      'ledger_journals',
      'payment_event_outbox',
      'payout_hold_requests',
      'payout_holds',
      'payouts',
      'provider_reconciliation_records',
    ]);
  });

  it('prevents updates and deletes to posted ledger records', async () => {
    const paymentId = randomUUID();
    const bookingId = randomUUID();
    const userId = randomUUID();

    await pool.query(
      `INSERT INTO payments
         (id, booking_id, user_id, amount_tzs, method, status, provider, internal_reference, payer_phone)
       VALUES ($1,$2,$3,10000,'mpesa_tz','completed','azampay',$4,'+255700000001')`,
      [paymentId, bookingId, userId, `RSHFY-${randomUUID().replace(/-/g, '').slice(0, 16)}`],
    );

    const cashAccount = await pool.query<{ id: string }>(
      `INSERT INTO ledger_accounts (owner_type, account_type, name)
       VALUES ('platform','cash','Platform cash')
       RETURNING id`,
    );
    const fundsAccount = await pool.query<{ id: string }>(
      `INSERT INTO ledger_accounts (owner_type, owner_id, account_type, name)
       VALUES ('passenger',$1,'passenger_funds','Passenger funds')
       RETURNING id`,
      [userId],
    );
    const journal = await pool.query<{ id: string }>(
      `INSERT INTO ledger_journals
         (journal_type, source_type, source_id, booking_id, payment_id, idempotency_key)
       VALUES ('payment_captured','payment',$3,$2,$1,$4)
       RETURNING id`,
      [paymentId, bookingId, paymentId, `payment:${paymentId}:captured`],
    );
    const entry = await pool.query<{ id: string }>(
      `INSERT INTO ledger_entries
         (journal_id, account_id, direction, amount_tzs, booking_id, payment_id, source_type, source_id)
       VALUES
         ($1,$2,'debit',10000,$4,$5,'payment',$6),
         ($1,$3,'credit',10000,$4,$5,'payment',$6)
       RETURNING id`,
      [journal.rows[0]!.id, cashAccount.rows[0]!.id, fundsAccount.rows[0]!.id, bookingId, paymentId, paymentId],
    );

    await expect(
      pool.query('UPDATE ledger_entries SET amount_tzs=9000 WHERE id=$1', [entry.rows[0]!.id]),
    ).rejects.toThrow(/append-only/);
    await expect(
      pool.query('DELETE FROM ledger_journals WHERE id=$1', [journal.rows[0]!.id]),
    ).rejects.toThrow(/append-only/);
  }, 60000);
});
