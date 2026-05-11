-- Development seed for a driver user.
-- Plaintext password: Rishfy@Driver2026

INSERT INTO auth_users (
  phone,
  email,
  password_hash,
  user_type,
  verified,
  status,
  profile_id
)
VALUES (
  '+255700000003',
  'driver@rishfy.co.tz',
  '9566d207008149220d67bc25ab784974:6a9b837fd0ae9bf715a80d8b3d131b0b25e27f1226059d9681c86db65c857017b11a06731d5dcd7423e639cfe4b2569ade089a622cb0cc73a5ddb371f51a981c',
  'driver',
  TRUE,
  'active',
  '46ae9964-a625-495e-94d4-f832638ddc15'
)
ON CONFLICT (email) DO UPDATE SET
  password_hash = EXCLUDED.password_hash,
  user_type     = EXCLUDED.user_type,
  verified      = EXCLUDED.verified,
  status        = EXCLUDED.status,
  profile_id    = EXCLUDED.profile_id;
