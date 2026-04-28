/* eslint-disable camelcase */
/** @type {import('node-pg-migrate').ColumnDefinitions | undefined} */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.createFunction(
    'update_updated_at_column',
    [],
    {
      returns: 'trigger',
      language: 'plpgsql',
    },
    `
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    `
  );

  pgm.createTable('auth_users', {
    id: 'id',
    phone: { type: 'varchar(20)', notNull: true, unique: true },
    email: { type: 'varchar(255)', unique: true },
    password_hash: { type: 'varchar(255)', notNull: true },
    user_type: {
      type: 'varchar(20)',
      notNull: true,
      check: "user_type IN ('driver', 'rider', 'admin')",
    },
    verified: { type: 'boolean', notNull: true, default: false },
    status: {
      type: 'varchar(20)',
      notNull: true,
      default: 'active',
      check: "status IN ('active', 'suspended', 'banned', 'deleted')",
    },
    last_login_at: { type: 'timestamptz' },
    failed_login_count: { type: 'integer', notNull: true, default: 0 },
    locked_until: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('NOW()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('NOW()') },
  });

  pgm.createIndex('auth_users', 'phone', { name: 'idx_auth_users_phone' });
  pgm.createIndex('auth_users', 'email', {
    name: 'idx_auth_users_email',
    where: 'email IS NOT NULL',
  });
  pgm.createIndex('auth_users', ['user_type', 'status'], {
    name: 'idx_auth_users_type_status',
  });

  pgm.createTrigger('auth_users', 'trg_auth_users_updated_at', {
    when: 'BEFORE',
    operation: 'UPDATE',
    level: 'ROW',
    function: 'update_updated_at_column',
  });

  pgm.createTable('verification_codes', {
    id: 'id',
    user_id: {
      type: 'integer',
      notNull: true,
      references: 'auth_users(id)',
      onDelete: 'CASCADE',
    },
    code: { type: 'varchar(6)', notNull: true },
    type: {
      type: 'varchar(30)',
      notNull: true,
      check: "type IN ('registration', 'login', 'password_reset', 'phone_change')",
    },
    attempts: { type: 'integer', notNull: true, default: 0 },
    max_attempts: { type: 'integer', notNull: true, default: 3 },
    expires_at: { type: 'timestamptz', notNull: true },
    used: { type: 'boolean', notNull: true, default: false },
    used_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('NOW()') },
  });

  pgm.createIndex('verification_codes', ['user_id', 'type'], {
    name: 'idx_verification_codes_user_type',
    where: 'used = FALSE',
  });
  pgm.createIndex('verification_codes', 'expires_at', {
    name: 'idx_verification_codes_expires',
    where: 'used = FALSE',
  });

  pgm.createTable('refresh_tokens', {
    id: 'id',
    user_id: {
      type: 'integer',
      notNull: true,
      references: 'auth_users(id)',
      onDelete: 'CASCADE',
    },
    token_hash: { type: 'varchar(255)', notNull: true, unique: true },
    device_info: { type: 'jsonb' },
    expires_at: { type: 'timestamptz', notNull: true },
    revoked: { type: 'boolean', notNull: true, default: false },
    revoked_at: { type: 'timestamptz' },
    revoked_reason: { type: 'varchar(100)' },
    last_used_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('NOW()') },
  });

  pgm.createIndex('refresh_tokens', 'user_id', {
    name: 'idx_refresh_tokens_user',
    where: 'revoked = FALSE',
  });
  pgm.createIndex('refresh_tokens', 'token_hash', { name: 'idx_refresh_tokens_hash' });
  pgm.createIndex('refresh_tokens', 'expires_at', {
    name: 'idx_refresh_tokens_expires',
    where: 'revoked = FALSE',
  });

  pgm.createTable('password_resets', {
    id: 'id',
    user_id: {
      type: 'integer',
      notNull: true,
      references: 'auth_users(id)',
      onDelete: 'CASCADE',
    },
    token_hash: { type: 'varchar(255)', notNull: true, unique: true },
    expires_at: { type: 'timestamptz', notNull: true },
    used: { type: 'boolean', notNull: true, default: false },
    used_at: { type: 'timestamptz' },
    ip_address: { type: 'inet' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('NOW()') },
  });

  pgm.createIndex('password_resets', 'user_id', {
    name: 'idx_password_resets_user',
    where: 'used = FALSE',
  });
};

exports.down = (pgm) => {
  pgm.dropTable('password_resets');
  pgm.dropTable('refresh_tokens');
  pgm.dropTable('verification_codes');
  pgm.dropTrigger('auth_users', 'trg_auth_users_updated_at', { ifExists: true });
  pgm.dropTable('auth_users');
  pgm.dropFunction('update_updated_at_column', []);
};
