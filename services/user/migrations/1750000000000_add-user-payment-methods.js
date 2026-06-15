/**
 * @type {import('node-pg-migrate').MigrationBuilder}
 */
exports.up = (pgm) => {
  pgm.createTable('user_payment_methods', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    user_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    label: { type: 'text', notNull: true, default: '' },
    provider: { type: 'text', notNull: true },
    phone: { type: 'text', notNull: true },
    is_default: { type: 'boolean', notNull: true, default: false },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    deleted_at: { type: 'timestamptz' },
  });
  pgm.createIndex('user_payment_methods', 'user_id');
  pgm.sql(`
    CREATE UNIQUE INDEX user_payment_methods_active_destination_uq
      ON user_payment_methods (user_id, provider, phone)
      WHERE deleted_at IS NULL;
  `);
  pgm.sql(`
    CREATE UNIQUE INDEX user_payment_methods_single_default_uq
      ON user_payment_methods (user_id)
      WHERE deleted_at IS NULL AND is_default = true;
  `);
};

exports.down = (pgm) => {
  pgm.dropTable('user_payment_methods');
};
