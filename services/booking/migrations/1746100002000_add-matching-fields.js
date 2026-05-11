/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.sql(`CREATE EXTENSION IF NOT EXISTS postgis`);

  pgm.sql(`ALTER TYPE booking_status ADD VALUE IF NOT EXISTS 'declined'`);

  pgm.addColumns('bookings', {
    declined_reason:          { type: 'text' },
    pickup_walking_distance:  { type: 'integer' },
    dropoff_walking_distance: { type: 'integer' },
    pickup_walking_time:      { type: 'integer' },
    estimated_pickup_time:    { type: 'timestamptz' },
    suggested_pickup_name:    { type: 'varchar(500)' },
  });

  pgm.sql(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS pickup_point  GEOGRAPHY(Point, 4326)`);
  pgm.sql(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS dropoff_point GEOGRAPHY(Point, 4326)`);
};

exports.down = (pgm) => {
  pgm.sql(`ALTER TABLE bookings DROP COLUMN IF EXISTS dropoff_point`);
  pgm.sql(`ALTER TABLE bookings DROP COLUMN IF EXISTS pickup_point`);
  pgm.dropColumns('bookings', [
    'declined_reason', 'pickup_walking_distance', 'dropoff_walking_distance',
    'pickup_walking_time', 'estimated_pickup_time', 'suggested_pickup_name',
  ]);
  // Note: cannot remove enum values in Postgres; declined stays in booking_status
};
