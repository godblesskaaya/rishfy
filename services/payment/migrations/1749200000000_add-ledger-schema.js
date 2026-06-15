/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('ledger_account_owner_type', ['platform', 'driver', 'passenger', 'provider']);
  pgm.createType('ledger_account_type', [
    'cash',
    'provider_clearing',
    'passenger_funds',
    'driver_payable',
    'platform_revenue',
    'refund_liability',
    'payout_clearing',
    'dispute_hold',
  ]);
  pgm.createType('ledger_journal_type', [
    'payment_captured',
    'driver_payable_accrued',
    'refund_requested',
    'refund_completed',
    'payout_initiated',
    'payout_completed',
    'payout_failed',
    'reversal',
    'adjustment',
  ]);
  pgm.createType('ledger_journal_status', ['posted', 'reversed']);
  pgm.createType('ledger_entry_direction', ['debit', 'credit']);

  pgm.createTable('ledger_accounts', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    owner_type: { type: 'ledger_account_owner_type', notNull: true },
    owner_id: { type: 'uuid' },
    account_type: { type: 'ledger_account_type', notNull: true },
    currency: { type: 'char(3)', notNull: true, default: 'TZS' },
    name: { type: 'varchar(120)', notNull: true },
    metadata: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.sql(`
    CREATE UNIQUE INDEX ledger_accounts_owner_account_currency_uq
      ON ledger_accounts (owner_type, COALESCE(owner_id::text, ''), account_type, currency);
  `);
  pgm.createIndex('ledger_accounts', ['owner_type', 'owner_id']);
  pgm.createIndex('ledger_accounts', ['account_type', 'currency']);

  pgm.createTable('ledger_journals', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    journal_type: { type: 'ledger_journal_type', notNull: true },
    status: { type: 'ledger_journal_status', notNull: true, default: 'posted' },
    source_type: { type: 'varchar(60)', notNull: true },
    source_id: { type: 'varchar(120)', notNull: true },
    booking_id: { type: 'uuid' },
    payment_id: { type: 'uuid', references: '"payments"', onDelete: 'RESTRICT' },
    settlement_id: { type: 'uuid', references: '"settlements"', onDelete: 'RESTRICT' },
    idempotency_key: { type: 'varchar(160)', notNull: true, unique: true },
    currency: { type: 'char(3)', notNull: true, default: 'TZS' },
    metadata: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
    created_by: { type: 'uuid' },
    correlation_id: { type: 'varchar(120)' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('ledger_journals', ['journal_type', 'created_at']);
  pgm.createIndex('ledger_journals', ['source_type', 'source_id']);
  pgm.createIndex('ledger_journals', 'booking_id', { where: 'booking_id IS NOT NULL' });
  pgm.createIndex('ledger_journals', 'payment_id', { where: 'payment_id IS NOT NULL' });
  pgm.createIndex('ledger_journals', 'settlement_id', { where: 'settlement_id IS NOT NULL' });

  pgm.createTable('ledger_entries', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    journal_id: { type: 'uuid', notNull: true, references: '"ledger_journals"', onDelete: 'RESTRICT' },
    account_id: { type: 'uuid', notNull: true, references: '"ledger_accounts"', onDelete: 'RESTRICT' },
    direction: { type: 'ledger_entry_direction', notNull: true },
    amount_tzs: { type: 'bigint', notNull: true, check: 'amount_tzs > 0' },
    currency: { type: 'char(3)', notNull: true, default: 'TZS' },
    booking_id: { type: 'uuid' },
    payment_id: { type: 'uuid', references: '"payments"', onDelete: 'RESTRICT' },
    settlement_id: { type: 'uuid', references: '"settlements"', onDelete: 'RESTRICT' },
    source_type: { type: 'varchar(60)', notNull: true },
    source_id: { type: 'varchar(120)', notNull: true },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('ledger_entries', 'journal_id');
  pgm.createIndex('ledger_entries', 'account_id');
  pgm.createIndex('ledger_entries', ['source_type', 'source_id']);
  pgm.createIndex('ledger_entries', 'booking_id', { where: 'booking_id IS NOT NULL' });
  pgm.createIndex('ledger_entries', 'payment_id', { where: 'payment_id IS NOT NULL' });
  pgm.createIndex('ledger_entries', 'settlement_id', { where: 'settlement_id IS NOT NULL' });

  pgm.sql(`
    CREATE OR REPLACE FUNCTION prevent_ledger_mutation()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'ledger records are append-only';
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER ledger_journals_no_update_delete
      BEFORE UPDATE OR DELETE ON ledger_journals
      FOR EACH ROW EXECUTE FUNCTION prevent_ledger_mutation();

    CREATE TRIGGER ledger_entries_no_update_delete
      BEFORE UPDATE OR DELETE ON ledger_entries
      FOR EACH ROW EXECUTE FUNCTION prevent_ledger_mutation();
  `);
};

exports.down = (pgm) => {
  pgm.sql(`
    DROP TRIGGER IF EXISTS ledger_entries_no_update_delete ON ledger_entries;
    DROP TRIGGER IF EXISTS ledger_journals_no_update_delete ON ledger_journals;
    DROP FUNCTION IF EXISTS prevent_ledger_mutation();
  `);
  pgm.dropTable('ledger_entries');
  pgm.dropTable('ledger_journals');
  pgm.dropTable('ledger_accounts');
  pgm.dropType('ledger_entry_direction');
  pgm.dropType('ledger_journal_status');
  pgm.dropType('ledger_journal_type');
  pgm.dropType('ledger_account_type');
  pgm.dropType('ledger_account_owner_type');
};
