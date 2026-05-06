-- Development seed for the initial admin auth identity.
-- Run after auth_db migrations and user_db user-profile migrations.
-- Password hash format: scrypt(password, salt, 64) — matches password.service.ts
-- Plaintext password: Rishfy@Admin2026

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
  '019f7b03fd17dc90626f8883ed69bc21:c631e3179edbbf0faae06ea252fa520cd8d85d7046d6a951149c02e1d66d34da0c3af00bb574dd9edc7175a49e64e304530514a3860e7b1b3b9bb665965735bf',
  'admin',
  TRUE,
  'active'
)
ON CONFLICT (email) DO UPDATE SET
  password_hash = EXCLUDED.password_hash,
  user_type     = EXCLUDED.user_type,
  verified      = EXCLUDED.verified,
  status        = EXCLUDED.status;
