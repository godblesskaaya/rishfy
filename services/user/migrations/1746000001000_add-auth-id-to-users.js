/**
 * @type {import('node-pg-migrate').MigrationBuilder}
 */
exports.up = (pgm) => {
  // auth_id stores the auth-service integer user ID as a string.
  // Used to look up the user profile from the JWT sub claim.
  pgm.addColumn('users', {
    auth_id: { type: 'text', unique: true },
  });

  pgm.createIndex('users', 'auth_id');
};

exports.down = (pgm) => {
  pgm.dropIndex('users', 'auth_id');
  pgm.dropColumn('users', 'auth_id');
};
