/* eslint-disable camelcase */
exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.sql(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);
  pgm.sql(`ALTER TABLE auth_users ADD COLUMN IF NOT EXISTS profile_id UUID UNIQUE`);

  // Align seeded dev users to their pre-existing user_db UUIDs so JWTs issued
  // after this migration still resolve to the same profile rows.
  pgm.sql(`UPDATE auth_users SET profile_id = '01357ea8-c7c8-431f-b0a6-0aa01c0adf61'::uuid
           WHERE email = 'user@rishfy.co.tz' AND profile_id IS NULL`);
  pgm.sql(`UPDATE auth_users SET profile_id = '46ae9964-a625-495e-94d4-f832638ddc15'::uuid
           WHERE email = 'driver@rishfy.co.tz' AND profile_id IS NULL`);

  // Backfill any remaining rows, then lock the column.
  pgm.sql(`UPDATE auth_users SET profile_id = uuid_generate_v4() WHERE profile_id IS NULL`);
  pgm.sql(`ALTER TABLE auth_users ALTER COLUMN profile_id SET NOT NULL`);
  pgm.sql(`ALTER TABLE auth_users ALTER COLUMN profile_id SET DEFAULT uuid_generate_v4()`);
};

exports.down = (pgm) => {
  pgm.sql(`ALTER TABLE auth_users ALTER COLUMN profile_id DROP DEFAULT`);
  pgm.sql(`ALTER TABLE auth_users ALTER COLUMN profile_id DROP NOT NULL`);
  pgm.sql(`ALTER TABLE auth_users DROP CONSTRAINT IF EXISTS auth_users_profile_id_key`);
  pgm.sql(`ALTER TABLE auth_users DROP COLUMN IF EXISTS profile_id`);
};
