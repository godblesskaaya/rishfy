/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = async (pgm) => {
  // Compress driver_locations segments older than 7 days, ordered by time DESC per driver
  pgm.sql(`
    ALTER TABLE driver_locations SET (
      timescaledb.compress,
      timescaledb.compress_segmentby = 'driver_id',
      timescaledb.compress_orderby   = 'time DESC'
    )
  `);
  pgm.sql(`SELECT add_compression_policy('driver_locations', INTERVAL '7 days')`);
};

exports.down = async (pgm) => {
  pgm.sql(`SELECT remove_compression_policy('driver_locations')`);
  pgm.sql(`ALTER TABLE driver_locations SET (timescaledb.compress = false)`);
};
