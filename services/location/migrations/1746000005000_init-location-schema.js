/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = async (pgm) => {
  pgm.createExtension('uuid-ossp', { ifNotExists: true });
  pgm.createExtension('timescaledb', { ifNotExists: true });

  pgm.createTable('driver_locations', {
    time: { type: 'timestamptz', notNull: true },
    driver_id: { type: 'uuid', notNull: true },
    trip_id: { type: 'uuid' },
    lat: { type: 'double precision', notNull: true },
    lng: { type: 'double precision', notNull: true },
    bearing: { type: 'smallint' },
    speed_kmh: { type: 'real' },
    accuracy_meters: { type: 'real' },
  });

  pgm.sql(`SELECT create_hypertable('driver_locations', 'time', if_not_exists => TRUE);`);

  pgm.createIndex('driver_locations', ['driver_id', 'time']);
  pgm.createIndex('driver_locations', 'trip_id', { where: 'trip_id IS NOT NULL' });

  pgm.createType('trip_status', ['pending', 'in_progress', 'completed', 'cancelled']);

  pgm.createTable('trips', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    booking_id: { type: 'uuid', notNull: true, unique: true },
    driver_id: { type: 'uuid', notNull: true },
    passenger_id: { type: 'uuid', notNull: true },

    status: { type: 'trip_status', notNull: true, default: 'pending' },

    origin_lat: { type: 'double precision', notNull: true },
    origin_lng: { type: 'double precision', notNull: true },
    destination_lat: { type: 'double precision', notNull: true },
    destination_lng: { type: 'double precision', notNull: true },

    path_encoded: { type: 'text' },
    total_distance_meters: { type: 'integer' },
    total_duration_seconds: { type: 'integer' },

    started_at: { type: 'timestamptz' },
    completed_at: { type: 'timestamptz' },
    cancelled_at: { type: 'timestamptz' },

    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('trips', 'driver_id');
  pgm.createIndex('trips', 'passenger_id');
  pgm.createIndex('trips', 'status');
  pgm.createIndex('trips', 'started_at');
};

exports.down = (pgm) => {
  pgm.dropTable('trips');
  pgm.dropType('trip_status');
  pgm.dropTable('driver_locations');
};
