/**
 * Make phone nullable now that email is the primary auth identifier.
 * The partial unique index already handles NULL correctly (NULLs are not equal).
 */
exports.up = (pgm) => {
  pgm.alterColumn('auth_users', 'phone', { notNull: false });
};

exports.down = (pgm) => {
  // Only reversible if all rows have a phone value.
  pgm.alterColumn('auth_users', 'phone', { notNull: true });
};
