/**
 * Sprint 3 prep — schema only, service not yet implemented.
 * @type {import('node-pg-migrate').MigrationBuilder}
 */
exports.up = (pgm) => {
  pgm.createExtension('uuid-ossp', { ifNotExists: true });

  pgm.createType('booking_status', [
    'pending',
    'confirmed',
    'driver_cancelled',
    'passenger_cancelled',
    'completed',
    'no_show',
  ]);

  pgm.createType('payment_status', ['unpaid', 'paid', 'refunded', 'failed']);

  pgm.createTable('bookings', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    route_id: { type: 'uuid', notNull: true },
    passenger_id: { type: 'uuid', notNull: true },
    driver_id: { type: 'uuid', notNull: true },

    seats_booked: { type: 'smallint', notNull: true, default: 1 },
    pickup_name: { type: 'varchar(500)' },
    dropoff_name: { type: 'varchar(500)' },

    total_price: { type: 'numeric(10,2)', notNull: true },
    status: { type: 'booking_status', notNull: true, default: 'pending' },
    payment_status: { type: 'payment_status', notNull: true, default: 'unpaid' },
    payment_reference: { type: 'varchar(255)' },

    confirmed_at: { type: 'timestamptz' },
    cancelled_at: { type: 'timestamptz' },
    cancellation_reason: { type: 'text' },
    completed_at: { type: 'timestamptz' },

    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('bookings', 'route_id');
  pgm.createIndex('bookings', 'passenger_id');
  pgm.createIndex('bookings', 'driver_id');
  pgm.createIndex('bookings', 'status');
  pgm.createIndex('bookings', 'payment_status');

  pgm.createTable('booking_events', {
    id: { type: 'bigserial', primaryKey: true },
    booking_id: { type: 'uuid', notNull: true, references: '"bookings"', onDelete: 'CASCADE' },
    event_type: { type: 'varchar(100)', notNull: true },
    payload: { type: 'jsonb' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('booking_events', 'booking_id');
};

exports.down = (pgm) => {
  pgm.dropTable('booking_events');
  pgm.dropTable('bookings');
  pgm.dropType('payment_status');
  pgm.dropType('booking_status');
};
