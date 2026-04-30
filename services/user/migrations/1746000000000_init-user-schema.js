/**
 * @type {import('node-pg-migrate').MigrationBuilder}
 */
exports.up = (pgm) => {
  pgm.createExtension('uuid-ossp', { ifNotExists: true });
  pgm.createExtension('pg_trgm', { ifNotExists: true });

  pgm.createType('user_role', ['passenger', 'driver', 'admin']);
  pgm.createType('user_status', ['active', 'suspended', 'pending_verification']);
  pgm.createType('vehicle_status', ['pending', 'approved', 'rejected']);
  pgm.createType('document_type', ['driving_license', 'vehicle_registration', 'insurance', 'latra_permit']);

  pgm.createTable('users', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    phone_number: { type: 'varchar(20)', notNull: true, unique: true },
    full_name: { type: 'varchar(255)', notNull: true },
    email: { type: 'varchar(255)', unique: true },
    role: { type: 'user_role', notNull: true, default: 'passenger' },
    status: { type: 'user_status', notNull: true, default: 'active' },
    profile_picture_url: { type: 'text' },
    average_rating: { type: 'numeric(3,2)', default: 0 },
    total_ratings: { type: 'integer', default: 0 },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createTable('driver_profiles', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    user_id: { type: 'uuid', notNull: true, unique: true, references: '"users"', onDelete: 'CASCADE' },
    license_number: { type: 'varchar(50)', notNull: true, unique: true },
    license_expiry: { type: 'date', notNull: true },
    latra_permit_number: { type: 'varchar(100)' },
    is_verified: { type: 'boolean', notNull: true, default: false },
    verified_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createTable('vehicles', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    driver_profile_id: { type: 'uuid', notNull: true, references: '"driver_profiles"', onDelete: 'CASCADE' },
    make: { type: 'varchar(100)', notNull: true },
    model: { type: 'varchar(100)', notNull: true },
    year: { type: 'integer', notNull: true },
    color: { type: 'varchar(50)', notNull: true },
    plate_number: { type: 'varchar(20)', notNull: true, unique: true },
    capacity: { type: 'integer', notNull: true, default: 4 },
    status: { type: 'vehicle_status', notNull: true, default: 'pending' },
    is_active: { type: 'boolean', notNull: true, default: false },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createTable('vehicle_documents', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    vehicle_id: { type: 'uuid', notNull: true, references: '"vehicles"', onDelete: 'CASCADE' },
    document_type: { type: 'document_type', notNull: true },
    file_url: { type: 'text', notNull: true },
    expires_at: { type: 'date' },
    uploaded_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createTable('devices', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    user_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    fcm_token: { type: 'text', notNull: true },
    platform: { type: 'varchar(10)', notNull: true }, // ios | android
    device_id: { type: 'varchar(255)', notNull: true },
    is_active: { type: 'boolean', notNull: true, default: true },
    last_seen_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.addConstraint('devices', 'devices_user_device_unique', 'UNIQUE (user_id, device_id)');

  pgm.createTable('ratings', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    ratee_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    rater_id: { type: 'uuid', notNull: true, references: '"users"', onDelete: 'CASCADE' },
    booking_id: { type: 'uuid', notNull: true },
    score: { type: 'smallint', notNull: true },
    comment: { type: 'text' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.addConstraint('ratings', 'ratings_score_range', 'CHECK (score >= 1 AND score <= 5)');
  pgm.addConstraint('ratings', 'ratings_booking_ratee_unique', 'UNIQUE (booking_id, ratee_id)');

  pgm.createIndex('users', 'phone_number');
  pgm.createIndex('driver_profiles', 'user_id');
  pgm.createIndex('vehicles', 'driver_profile_id');
  pgm.createIndex('devices', 'user_id');
  pgm.createIndex('ratings', 'ratee_id');
};

exports.down = (pgm) => {
  pgm.dropTable('ratings');
  pgm.dropTable('devices');
  pgm.dropTable('vehicle_documents');
  pgm.dropTable('vehicles');
  pgm.dropTable('driver_profiles');
  pgm.dropTable('users');
  pgm.dropType('document_type');
  pgm.dropType('vehicle_status');
  pgm.dropType('user_status');
  pgm.dropType('user_role');
};
