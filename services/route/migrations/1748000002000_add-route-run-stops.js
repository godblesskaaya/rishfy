/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('route_run_stop_kind', ['pickup', 'dropoff']);
  pgm.createType('route_run_stop_status', ['pending', 'active', 'completed', 'skipped']);

  pgm.createTable('route_run_stops', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    route_run_id: {
      type: 'uuid',
      notNull: true,
      references: '"route_runs"',
      onDelete: 'CASCADE',
    },
    booking_id: { type: 'uuid', notNull: true },
    stop_kind: { type: 'route_run_stop_kind', notNull: true },
    sequence: { type: 'integer', notNull: true },
    status: { type: 'route_run_stop_status', notNull: true, default: 'pending' },
    stop_name: { type: 'varchar(500)' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('route_run_stops', ['route_run_id']);
  pgm.addConstraint(
    'route_run_stops',
    'route_run_stops_route_sequence_unique',
    'UNIQUE (route_run_id, sequence)',
  );
};

exports.down = (pgm) => {
  pgm.dropTable('route_run_stops');
  pgm.dropType('route_run_stop_status');
  pgm.dropType('route_run_stop_kind');
};

