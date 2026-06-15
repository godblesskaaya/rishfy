/**
 * @type {import('node-pg-migrate').MigrationBuilder}
 */
exports.up = (pgm) => {
  pgm.createType('rating_moderation_status', ['pending', 'approved', 'hidden']);

  pgm.addColumns('ratings', {
    moderation_status: { type: 'rating_moderation_status', notNull: true, default: 'pending' },
    moderated_by: { type: 'uuid', references: '"users"', onDelete: 'SET NULL' },
    moderated_at: { type: 'timestamptz' },
    hidden_reason: { type: 'text' },
  });
  pgm.createIndex('ratings', ['moderation_status', 'created_at']);

  pgm.createTable('user_blocks', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    blocker_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    blocked_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    reason: { type: 'text' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    deleted_at: { type: 'timestamptz' },
  });
  pgm.addConstraint('user_blocks', 'user_blocks_no_self_block', 'CHECK (blocker_id <> blocked_id)');
  pgm.createIndex('user_blocks', 'blocker_id');
  pgm.createIndex('user_blocks', 'blocked_id');
  pgm.sql(`
    CREATE UNIQUE INDEX user_blocks_active_pair_uq
      ON user_blocks (blocker_id, blocked_id)
      WHERE deleted_at IS NULL;
  `);

  pgm.createTable('favorite_drivers', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    passenger_user_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    driver_user_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    deleted_at: { type: 'timestamptz' },
  });
  pgm.addConstraint('favorite_drivers', 'favorite_drivers_no_self_favorite', 'CHECK (passenger_user_id <> driver_user_id)');
  pgm.createIndex('favorite_drivers', 'passenger_user_id');
  pgm.createIndex('favorite_drivers', 'driver_user_id');
  pgm.sql(`
    CREATE UNIQUE INDEX favorite_drivers_active_pair_uq
      ON favorite_drivers (passenger_user_id, driver_user_id)
      WHERE deleted_at IS NULL;
  `);
};

exports.down = (pgm) => {
  pgm.dropTable('favorite_drivers');
  pgm.dropTable('user_blocks');
  pgm.dropIndex('ratings', ['moderation_status', 'created_at']);
  pgm.dropColumns('ratings', ['moderation_status', 'moderated_by', 'moderated_at', 'hidden_reason']);
  pgm.dropType('rating_moderation_status');
};
