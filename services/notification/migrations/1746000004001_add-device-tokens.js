/**
 * @type {import('node-pg-migrate').MigrationBuilder}
 */
exports.up = (pgm) => {
  pgm.createTable('device_tokens', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('gen_random_uuid()') },
    user_id: { type: 'uuid', notNull: true },
    device_id: { type: 'text', notNull: true },
    fcm_token: { type: 'text', notNull: true },
    platform: { type: 'text', notNull: true, check: "platform IN ('ios', 'android')" },
    app_version: { type: 'text' },
    is_active: { type: 'boolean', notNull: true, default: true },
    last_used_at: { type: 'timestamptz', default: pgm.func('now()') },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  // One active token per device
  pgm.addConstraint('device_tokens', 'device_tokens_user_device_unique', 'UNIQUE (user_id, device_id)');

  pgm.createIndex('device_tokens', 'user_id');
  pgm.createIndex('device_tokens', 'fcm_token');

  // Lookup active tokens for a user quickly
  pgm.createIndex('device_tokens', ['user_id', 'is_active']);
};

exports.down = (pgm) => {
  pgm.dropTable('device_tokens');
};
