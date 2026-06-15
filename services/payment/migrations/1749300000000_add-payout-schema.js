/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('payout_status', ['pending_review', 'processing', 'completed', 'failed', 'cancelled']);

  pgm.createTable('payouts', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    driver_user_id: { type: 'uuid', notNull: true },
    amount_tzs: { type: 'bigint', notNull: true, check: 'amount_tzs > 0' },
    currency: { type: 'char(3)', notNull: true, default: 'TZS' },
    status: { type: 'payout_status', notNull: true, default: 'pending_review' },
    payout_method: { type: 'payment_method_type', notNull: true },
    payout_phone: { type: 'varchar(20)', notNull: true },
    requested_by: { type: 'uuid', notNull: true },
    reviewed_by: { type: 'uuid' },
    provider_reference: { type: 'varchar(255)' },
    failure_reason: { type: 'text' },
    requested_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    reviewed_at: { type: 'timestamptz' },
    processing_at: { type: 'timestamptz' },
    completed_at: { type: 'timestamptz' },
    failed_at: { type: 'timestamptz' },
    cancelled_at: { type: 'timestamptz' },
    metadata: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('payouts', 'driver_user_id');
  pgm.createIndex('payouts', ['status', 'created_at']);

  pgm.createTable('payout_items', {
    id: { type: 'bigserial', primaryKey: true },
    payout_id: { type: 'uuid', notNull: true, references: '"payouts"', onDelete: 'CASCADE' },
    ledger_entry_id: { type: 'uuid', notNull: true, references: '"ledger_entries"', onDelete: 'RESTRICT' },
    booking_id: { type: 'uuid' },
    amount_tzs: { type: 'bigint', notNull: true, check: 'amount_tzs > 0' },
    released_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('payout_items', 'payout_id');
  pgm.createIndex('payout_items', 'booking_id', { where: 'booking_id IS NOT NULL' });
  pgm.sql(`
    CREATE UNIQUE INDEX payout_items_active_ledger_entry_uq
      ON payout_items (ledger_entry_id)
      WHERE released_at IS NULL;
  `);
};

exports.down = (pgm) => {
  pgm.dropTable('payout_items');
  pgm.dropTable('payouts');
  pgm.dropType('payout_status');
};
