/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createTable('notification_preferences', {
    user_id: { type: 'uuid', notNull: true },
    category: { type: 'varchar(40)', notNull: true },
    enabled: { type: 'boolean', notNull: true, default: true },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });
  pgm.addConstraint('notification_preferences', 'notification_preferences_pk', {
    primaryKey: ['user_id', 'category'],
  });
};

exports.down = (pgm) => {
  pgm.dropTable('notification_preferences');
};
