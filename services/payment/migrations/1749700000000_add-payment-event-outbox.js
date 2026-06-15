/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createTable('payment_event_outbox', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    event_key: { type: 'varchar(180)', notNull: true, unique: true },
    topic: { type: 'varchar(120)', notNull: true },
    message_key: { type: 'varchar(120)', notNull: true },
    payload: { type: 'jsonb', notNull: true },
    status: {
      type: 'varchar(20)',
      notNull: true,
      default: 'pending',
      check: "status IN ('pending','publishing','published','dead')",
    },
    attempts: { type: 'integer', notNull: true, default: 0, check: 'attempts >= 0' },
    next_attempt_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    locked_at: { type: 'timestamptz' },
    published_at: { type: 'timestamptz' },
    last_error: { type: 'text' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('payment_event_outbox', ['status', 'next_attempt_at']);
  pgm.createIndex('payment_event_outbox', 'created_at');
};

exports.down = (pgm) => {
  pgm.dropTable('payment_event_outbox');
};
