exports.up = (pgm) => {
  pgm.sql(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS dropoff_walking_time integer`);
  pgm.sql(`ALTER TABLE bookings ADD COLUMN IF NOT EXISTS suggested_dropoff_name varchar(500)`);
};

exports.down = (pgm) => {
  pgm.sql(`ALTER TABLE bookings DROP COLUMN IF EXISTS dropoff_walking_time`);
  pgm.sql(`ALTER TABLE bookings DROP COLUMN IF EXISTS suggested_dropoff_name`);
};
