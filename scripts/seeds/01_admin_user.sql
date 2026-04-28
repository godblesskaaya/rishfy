-- Development seed for the initial admin auth identity.
-- Run after auth_db migrations and user_db user-profile migrations.

INSERT INTO auth_users (
  phone,
  email,
  password_hash,
  user_type,
  verified,
  status
)
VALUES (
  '+255700000001',
  'admin@rishfy.co.tz',
  '$2b$10$2b2f5D1R3A7P9sP9G4mGQ.0x1mJx4n7Yj2sZkP7A7mW0o4x9J9V4a',
  'admin',
  TRUE,
  'active'
)
ON CONFLICT (email) DO NOTHING;
