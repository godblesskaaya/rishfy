/**
 * @type {import('node-pg-migrate').MigrationBuilder}
 */
exports.up = (pgm) => {
  pgm.createExtension('uuid-ossp', { ifNotExists: true });
  pgm.createExtension('postgis', { ifNotExists: true });

  pgm.createType('route_status', ['draft', 'active', 'full', 'cancelled', 'completed']);
  pgm.createType('recurrence_type', ['none', 'daily', 'weekdays', 'weekly', 'custom']);

  pgm.createTable('routes', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    driver_id: { type: 'uuid', notNull: true },
    vehicle_id: { type: 'uuid', notNull: true },

    origin_name: { type: 'varchar(500)', notNull: true },
    origin_point: { type: 'geography(Point, 4326)', notNull: true },
    destination_name: { type: 'varchar(500)', notNull: true },
    destination_point: { type: 'geography(Point, 4326)', notNull: true },

    // Encoded Google Maps polyline for the route path
    polyline: { type: 'text' },
    distance_meters: { type: 'integer' },
    duration_seconds: { type: 'integer' },

    available_seats: { type: 'smallint', notNull: true },
    booked_seats: { type: 'smallint', notNull: true, default: 0 },
    price_per_seat: { type: 'numeric(10,2)', notNull: true },

    departure_time: { type: 'timestamptz', notNull: true },
    status: { type: 'route_status', notNull: true, default: 'active' },

    recurrence: { type: 'recurrence_type', notNull: true, default: 'none' },
    recurrence_days: { type: 'integer[]' }, // 0=Sun..6=Sat for custom
    recurrence_end_date: { type: 'date' },
    parent_route_id: { type: 'uuid' }, // for generated recurrences

    // Denormalised driver info to avoid gRPC on every list
    driver_name: { type: 'varchar(255)' },
    driver_rating: { type: 'numeric(3,2)' },
    vehicle_make: { type: 'varchar(100)' },
    vehicle_model: { type: 'varchar(100)' },
    vehicle_color: { type: 'varchar(50)' },
    vehicle_plate: { type: 'varchar(20)' },

    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  // GIST indexes for spatial queries
  pgm.createIndex('routes', 'origin_point', { method: 'gist' });
  pgm.createIndex('routes', 'destination_point', { method: 'gist' });
  pgm.createIndex('routes', ['driver_id']);
  pgm.createIndex('routes', ['status']);
  pgm.createIndex('routes', ['departure_time']);
  pgm.createIndex('routes', ['parent_route_id']);

  // Waypoints table for multi-stop routes (Sprint 3+)
  pgm.createTable('route_waypoints', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    route_id: { type: 'uuid', notNull: true, references: '"routes"', onDelete: 'CASCADE' },
    name: { type: 'varchar(500)', notNull: true },
    point: { type: 'geography(Point, 4326)', notNull: true },
    sequence: { type: 'smallint', notNull: true },
  });

  pgm.createIndex('route_waypoints', 'route_id');
  pgm.addConstraint('route_waypoints', 'route_waypoints_sequence_unique', 'UNIQUE (route_id, sequence)');
};

exports.down = (pgm) => {
  pgm.dropTable('route_waypoints');
  pgm.dropTable('routes');
  pgm.dropType('recurrence_type');
  pgm.dropType('route_status');
};
