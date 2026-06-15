/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createTable('payout_hold_requests', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    booking_id: { type: 'uuid', notNull: true },
    driver_user_id: { type: 'uuid', notNull: true },
    requested_by: { type: 'uuid', notNull: true },
    reason: { type: 'payout_hold_reason', notNull: true, default: 'safety_report' },
    note: { type: 'text' },
    status: {
      type: 'varchar(20)',
      notNull: true,
      default: 'pending',
      check: "status IN ('pending','applied','ignored')",
    },
    payout_hold_id: { type: 'uuid', references: '"payout_holds"', onDelete: 'SET NULL' },
    applied_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('payout_hold_requests', 'booking_id');
  pgm.createIndex('payout_hold_requests', ['status', 'created_at']);
  pgm.sql(`
    CREATE UNIQUE INDEX payout_hold_requests_pending_booking_uq
      ON payout_hold_requests (booking_id)
      WHERE status='pending';
  `);
};

exports.down = (pgm) => {
  pgm.dropTable('payout_hold_requests');
};
