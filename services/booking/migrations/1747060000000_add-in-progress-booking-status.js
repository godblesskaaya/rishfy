/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.sql(`ALTER TYPE booking_status ADD VALUE IF NOT EXISTS 'in_progress'`);
};

exports.down = () => {
  // Postgres enums cannot drop values safely; keep the added value on rollback.
};
