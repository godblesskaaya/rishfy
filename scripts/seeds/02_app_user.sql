-- Development seed for a passenger (app) user.
-- Plaintext password: Rishfy@User2026

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
  '+255700000002',
  'user@rishfy.co.tz',
  '0c9fbfb919a4bed500252e2045778f6d:ae161efd28eea384bb988a3e68f42d31688106199a24dee29a986da441f924054b4fc961d2ca8b5faa295a4489495610238f3df3cf6788f610f7bd014666c29f',
  'rider',
  TRUE,
  'active',
  '01357ea8-c7c8-431f-b0a6-0aa01c0adf61'
)
ON CONFLICT (email) DO UPDATE SET
  password_hash = EXCLUDED.password_hash,
  user_type     = EXCLUDED.user_type,
  verified      = EXCLUDED.verified,
  status        = EXCLUDED.status,
  profile_id    = EXCLUDED.profile_id;
