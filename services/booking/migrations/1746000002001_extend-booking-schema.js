/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.addColumns('bookings', {
    confirmation_code: { type: 'varchar(8)', unique: true },
    expires_at: { type: 'timestamptz' },
    seat_count: { type: 'smallint', notNull: true, default: 1 },
    platform_fee: { type: 'numeric(10,2)', notNull: true, default: 0 },
    driver_earnings: { type: 'numeric(10,2)', notNull: true, default: 0 },
    pickup_lat: { type: 'double precision' },
    pickup_lng: { type: 'double precision' },
    dropoff_lat: { type: 'double precision' },
    dropoff_lng: { type: 'double precision' },
    idempotency_key: { type: 'varchar(100)', unique: true },
    trip_started_at: { type: 'timestamptz' },
    trip_completed_at: { type: 'timestamptz' },
    passenger_rating: { type: 'smallint' },
    driver_rating: { type: 'smallint' },
    passenger_review: { type: 'text' },
    driver_review: { type: 'text' },
    payment_id: { type: 'uuid' },
    cancellation_policy: { type: 'varchar(20)' },
  });

  pgm.createIndex('bookings', 'confirmation_code', { where: 'confirmation_code IS NOT NULL' });
  pgm.createIndex('bookings', 'expires_at', { where: 'expires_at IS NOT NULL AND status = \'pending\'' });
  pgm.createIndex('bookings', 'idempotency_key', { where: 'idempotency_key IS NOT NULL' });
};

exports.down = (pgm) => {
  pgm.dropColumns('bookings', [
    'confirmation_code', 'expires_at', 'seat_count', 'platform_fee', 'driver_earnings',
    'pickup_lat', 'pickup_lng', 'dropoff_lat', 'dropoff_lng', 'idempotency_key',
    'trip_started_at', 'trip_completed_at', 'passenger_rating', 'driver_rating',
    'passenger_review', 'driver_review', 'payment_id', 'cancellation_policy',
  ]);
};
