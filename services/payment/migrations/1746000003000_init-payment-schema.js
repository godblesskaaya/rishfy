/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createExtension('uuid-ossp', { ifNotExists: true });

  pgm.createType('payment_txn_status', ['pending', 'processing', 'completed', 'failed', 'refunded', 'partially_refunded']);
  pgm.createType('payment_method_type', ['mpesa_tz', 'tigopesa', 'airtel_money', 'halopesa', 'mock']);
  pgm.createType('settlement_status', ['pending', 'processing', 'completed', 'failed']);

  pgm.createTable('payments', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    booking_id: { type: 'uuid', notNull: true },
    user_id: { type: 'uuid', notNull: true },
    idempotency_key: { type: 'varchar(100)', unique: true },

    amount_tzs: { type: 'bigint', notNull: true },
    method: { type: 'payment_method_type', notNull: true },
    status: { type: 'payment_txn_status', notNull: true, default: 'pending' },

    provider: { type: 'varchar(50)', notNull: true },
    provider_reference: { type: 'varchar(255)' },
    internal_reference: { type: 'varchar(100)', notNull: true, unique: true },

    payer_phone: { type: 'varchar(20)', notNull: true },
    failure_code: { type: 'varchar(100)' },
    failure_message: { type: 'text' },

    refunded_amount_tzs: { type: 'bigint', notNull: true, default: 0 },

    initiated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    completed_at: { type: 'timestamptz' },
    failed_at: { type: 'timestamptz' },
    last_refund_at: { type: 'timestamptz' },
    expires_at: { type: 'timestamptz' },

    raw_callback_payload: { type: 'jsonb' },
    metadata: { type: 'jsonb', default: "'{}'" },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('payments', 'booking_id');
  pgm.createIndex('payments', 'user_id');
  pgm.createIndex('payments', 'status');
  pgm.createIndex('payments', 'provider_reference', { where: 'provider_reference IS NOT NULL' });
  pgm.createIndex('payments', 'initiated_at');

  pgm.createTable('payment_callbacks', {
    id: { type: 'bigserial', primaryKey: true },
    payment_id: { type: 'uuid', references: '"payments"', onDelete: 'SET NULL' },
    provider: { type: 'varchar(50)', notNull: true },
    raw_payload: { type: 'text', notNull: true },
    signature: { type: 'varchar(500)' },
    verified: { type: 'boolean', notNull: true, default: false },
    processed: { type: 'boolean', notNull: true, default: false },
    error: { type: 'text' },
    received_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('payment_callbacks', 'payment_id');
  pgm.createIndex('payment_callbacks', 'received_at');

  pgm.createTable('settlements', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    driver_user_id: { type: 'uuid', notNull: true },
    period_start: { type: 'timestamptz', notNull: true },
    period_end: { type: 'timestamptz', notNull: true },

    total_amount_tzs: { type: 'bigint', notNull: true },
    platform_fee_tzs: { type: 'bigint', notNull: true },
    net_amount_tzs: { type: 'bigint', notNull: true },
    booking_count: { type: 'integer', notNull: true },

    payout_method: { type: 'payment_method_type', notNull: true },
    payout_phone: { type: 'varchar(20)', notNull: true },
    status: { type: 'settlement_status', notNull: true, default: 'pending' },

    provider_reference: { type: 'varchar(255)' },
    failure_reason: { type: 'text' },

    initiated_at: { type: 'timestamptz' },
    completed_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('settlements', 'driver_user_id');
  pgm.createIndex('settlements', 'status');
  pgm.createIndex('settlements', ['period_start', 'period_end']);

  pgm.createTable('settlement_bookings', {
    settlement_id: { type: 'uuid', notNull: true, references: '"settlements"', onDelete: 'CASCADE' },
    booking_id: { type: 'uuid', notNull: true },
    driver_earnings_tzs: { type: 'bigint', notNull: true },
  });

  pgm.addConstraint('settlement_bookings', 'settlement_bookings_pk', 'PRIMARY KEY (settlement_id, booking_id)');
};

exports.down = (pgm) => {
  pgm.dropTable('settlement_bookings');
  pgm.dropTable('settlements');
  pgm.dropTable('payment_callbacks');
  pgm.dropTable('payments');
  pgm.dropType('settlement_status');
  pgm.dropType('payment_method_type');
  pgm.dropType('payment_txn_status');
};
