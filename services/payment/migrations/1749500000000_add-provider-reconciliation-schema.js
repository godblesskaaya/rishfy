/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('reconciliation_record_type', ['payment', 'refund', 'payout']);
  pgm.createType('reconciliation_status', ['matched', 'unmatched', 'amount_mismatch', 'status_mismatch']);

  pgm.createTable('provider_reconciliation_records', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    provider: { type: 'varchar(50)', notNull: true },
    record_type: { type: 'reconciliation_record_type', notNull: true },
    provider_reference: { type: 'varchar(255)', notNull: true },
    amount_tzs: { type: 'bigint', notNull: true, check: 'amount_tzs > 0' },
    provider_status: { type: 'varchar(60)', notNull: true },
    occurred_at: { type: 'timestamptz' },
    match_status: { type: 'reconciliation_status', notNull: true },
    matched_payment_id: { type: 'uuid', references: '"payments"', onDelete: 'SET NULL' },
    mismatch_reason: { type: 'text' },
    raw_payload: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
    imported_by: { type: 'uuid', notNull: true },
    imported_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.addConstraint(
    'provider_reconciliation_records',
    'provider_reconciliation_record_unique',
    'UNIQUE (provider, record_type, provider_reference)'
  );
  pgm.createIndex('provider_reconciliation_records', ['match_status', 'created_at']);
  pgm.createIndex('provider_reconciliation_records', 'matched_payment_id', { where: 'matched_payment_id IS NOT NULL' });
};

exports.down = (pgm) => {
  pgm.dropTable('provider_reconciliation_records');
  pgm.dropType('reconciliation_status');
  pgm.dropType('reconciliation_record_type');
};
