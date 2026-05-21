/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('booking_journey_state', [
    'confirmed',
    'driver_approaching',
    'driver_arrived',
    'boarded',
    'in_transit',
    'dropped_off',
    'walking_to_destination',
    'completed',
    'cancelled',
    'no_show',
  ]);

  pgm.addColumns('bookings', {
    journey_state: { type: 'booking_journey_state' },
    trip_id: { type: 'uuid' },
    arrived_pickup_at: { type: 'timestamptz' },
    boarded_at: { type: 'timestamptz' },
    dropped_off_at: { type: 'timestamptz' },
    journey_completed_at: { type: 'timestamptz' },
    no_show_at: { type: 'timestamptz' },
  });

  pgm.sql(`
    UPDATE bookings
    SET journey_state = CASE
      WHEN status = 'confirmed' THEN 'confirmed'::booking_journey_state
      WHEN status = 'completed' THEN 'completed'::booking_journey_state
      WHEN status = 'no_show' THEN 'no_show'::booking_journey_state
      WHEN status IN ('passenger_cancelled', 'driver_cancelled') THEN 'cancelled'::booking_journey_state
      ELSE journey_state
    END,
    journey_completed_at = CASE
      WHEN status = 'completed' THEN COALESCE(journey_completed_at, completed_at, trip_completed_at, now())
      ELSE journey_completed_at
    END,
    no_show_at = CASE
      WHEN status = 'no_show' THEN COALESCE(no_show_at, cancelled_at, now())
      ELSE no_show_at
    END
  `);

  pgm.createIndex('bookings', 'journey_state', { where: 'journey_state IS NOT NULL' });
  pgm.createIndex('bookings', 'trip_id', { where: 'trip_id IS NOT NULL' });
};

exports.down = (pgm) => {
  pgm.dropColumns('bookings', [
    'journey_state',
    'trip_id',
    'arrived_pickup_at',
    'boarded_at',
    'dropped_off_at',
    'journey_completed_at',
    'no_show_at',
  ]);
  pgm.dropType('booking_journey_state');
};
