/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('refund_status', ['requested', 'processing', 'completed', 'failed', 'manual_required']);

  pgm.createTable('refunds', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    payment_id: { type: 'uuid', notNull: true, references: '"payments"', onDelete: 'RESTRICT' },
    booking_id: { type: 'uuid', notNull: true },
    user_id: { type: 'uuid', notNull: true },
    amount_tzs: { type: 'bigint', notNull: true, check: 'amount_tzs > 0' },
    status: { type: 'refund_status', notNull: true, default: 'requested' },
    reason: { type: 'text', notNull: true },
    policy: { type: 'varchar(40)', notNull: true },
    provider_reference: { type: 'varchar(255)' },
    failure_reason: { type: 'text' },
    requested_by: { type: 'uuid', notNull: true },
    requested_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    completed_at: { type: 'timestamptz' },
    failed_at: { type: 'timestamptz' },
    metadata: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('refunds', 'payment_id');
  pgm.createIndex('refunds', 'booking_id');
  pgm.createIndex('refunds', ['status', 'created_at']);
};

exports.down = (pgm) => {
  pgm.dropTable('refunds');
  pgm.dropType('refund_status');
};
