/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('support_case_status', ['open', 'waiting', 'resolved', 'closed']);
  pgm.createType('support_case_priority', ['low', 'normal', 'high', 'urgent']);

  pgm.createTable('user_support_cases', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    user_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    booking_id: { type: 'uuid' },
    subject: { type: 'varchar(160)', notNull: true },
    message: { type: 'text', notNull: true },
    category: { type: 'varchar(60)', notNull: true, default: 'general' },
    status: { type: 'support_case_status', notNull: true, default: 'open' },
    priority: { type: 'support_case_priority', notNull: true, default: 'normal' },
    last_user_message_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    last_support_response_at: { type: 'timestamptz' },
    resolved_at: { type: 'timestamptz' },
    closed_at: { type: 'timestamptz' },
    metadata: { type: 'jsonb', notNull: true, default: pgm.func("'{}'::jsonb") },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('user_support_cases', ['user_id', 'created_at']);
  pgm.createIndex('user_support_cases', ['status', 'priority', 'created_at']);
  pgm.createIndex('user_support_cases', 'booking_id');
};

exports.down = (pgm) => {
  pgm.dropTable('user_support_cases');
  pgm.dropType('support_case_priority');
  pgm.dropType('support_case_status');
};
