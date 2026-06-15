/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createType('payout_hold_reason', ['safety_report', 'dispute', 'no_show', 'chargeback', 'admin_review']);

  pgm.createTable('payout_holds', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    driver_user_id: { type: 'uuid', notNull: true },
    ledger_entry_id: { type: 'uuid', notNull: true, references: '"ledger_entries"', onDelete: 'RESTRICT' },
    booking_id: { type: 'uuid' },
    amount_tzs: { type: 'bigint', notNull: true, check: 'amount_tzs > 0' },
    reason: { type: 'payout_hold_reason', notNull: true },
    note: { type: 'text' },
    created_by: { type: 'uuid', notNull: true },
    released_by: { type: 'uuid' },
    released_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('payout_holds', 'driver_user_id');
  pgm.createIndex('payout_holds', 'booking_id', { where: 'booking_id IS NOT NULL' });
  pgm.sql(`
    CREATE UNIQUE INDEX payout_holds_active_ledger_entry_uq
      ON payout_holds (ledger_entry_id)
      WHERE released_at IS NULL;
  `);
};

exports.down = (pgm) => {
  pgm.dropTable('payout_holds');
  pgm.dropType('payout_hold_reason');
};
