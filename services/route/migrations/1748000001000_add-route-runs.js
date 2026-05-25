/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('route_run_status', [
    'scheduled',
    'active',
    'completed',
    'cancelled',
  ]);

  pgm.createTable('route_runs', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    route_id: {
      type: 'uuid',
      notNull: true,
      references: '"routes"',
      onDelete: 'CASCADE',
    },
    driver_id: { type: 'uuid', notNull: true },
    status: { type: 'route_run_status', notNull: true, default: 'scheduled' },
    started_at: { type: 'timestamptz' },
    completed_at: { type: 'timestamptz' },
    cancelled_at: { type: 'timestamptz' },
    current_stop_index: { type: 'integer', notNull: true, default: 0 },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('route_runs', ['route_id']);
  pgm.createIndex('route_runs', ['driver_id']);
  pgm.createIndex('route_runs', ['status']);
  pgm.sql(`
    CREATE UNIQUE INDEX route_runs_one_open_run_per_route
    ON route_runs (route_id)
    WHERE status IN ('scheduled', 'active')
  `);
};

exports.down = (pgm) => {
  pgm.sql('DROP INDEX IF EXISTS route_runs_one_open_run_per_route');
  pgm.dropTable('route_runs');
  pgm.dropType('route_run_status');
};
