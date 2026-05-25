/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.addColumns('driver_locations', {
    route_run_id: { type: 'uuid' },
  });

  pgm.addColumns('trips', {
    route_id: { type: 'uuid' },
    route_run_id: { type: 'uuid' },
  });

  pgm.sql(`ALTER TABLE trips ALTER COLUMN booking_id DROP NOT NULL`);
  pgm.sql(`ALTER TABLE trips ALTER COLUMN passenger_id DROP NOT NULL`);

  pgm.createIndex('driver_locations', 'route_run_id', {
    ifNotExists: true,
    where: 'route_run_id IS NOT NULL',
  });
  pgm.createIndex('trips', 'route_id', { ifNotExists: true });
  pgm.createIndex('trips', 'route_run_id', {
    ifNotExists: true,
    where: 'route_run_id IS NOT NULL',
  });
  pgm.addConstraint(
    'trips',
    'trips_route_run_id_unique',
    'UNIQUE (route_run_id)',
  );
};

exports.down = (pgm) => {
  pgm.dropConstraint('trips', 'trips_route_run_id_unique', { ifExists: true });
  pgm.dropIndex('trips', 'route_run_id', { ifExists: true });
  pgm.dropIndex('trips', 'route_id', { ifExists: true });
  pgm.dropIndex('driver_locations', 'route_run_id', { ifExists: true });
  pgm.dropColumns('driver_locations', ['route_run_id']);
  pgm.dropColumns('trips', ['route_id', 'route_run_id']);
  // booking_id/passenger_id nullability intentionally not restored in down migration
};
