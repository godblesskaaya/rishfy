/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.createExtension('uuid-ossp', { ifNotExists: true });

  pgm.createType('notification_channel', ['sms', 'push', 'in_app', 'email']);
  pgm.createType('notification_status', ['pending', 'queued', 'delivered', 'failed', 'skipped']);

  pgm.createTable('notification_templates', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    key: { type: 'varchar(100)', notNull: true },
    lang: { type: 'varchar(5)', notNull: true, default: "'en'" },
    channel: { type: 'notification_channel', notNull: true },
    subject: { type: 'varchar(255)' },
    body_template: { type: 'text', notNull: true },
    variables: { type: 'jsonb', default: "'[]'" },
    is_active: { type: 'boolean', notNull: true, default: true },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.addConstraint('notification_templates', 'notification_templates_key_lang_channel_unique',
    'UNIQUE (key, lang, channel)');

  pgm.createTable('notifications', {
    id: { type: 'uuid', primaryKey: true, default: pgm.func('uuid_generate_v4()') },
    user_id: { type: 'uuid', notNull: true },
    template_key: { type: 'varchar(100)', notNull: true },
    channel: { type: 'notification_channel', notNull: true },
    status: { type: 'notification_status', notNull: true, default: 'pending' },

    title: { type: 'varchar(255)' },
    body: { type: 'text', notNull: true },

    data: { type: 'jsonb', default: "'{}'" },
    is_read: { type: 'boolean', notNull: true, default: false },
    read_at: { type: 'timestamptz' },

    provider_message_id: { type: 'varchar(255)' },
    failure_reason: { type: 'text' },
    retry_count: { type: 'smallint', notNull: true, default: 0 },

    source_event_type: { type: 'varchar(100)' },
    source_event_id: { type: 'varchar(255)' },

    scheduled_for: { type: 'timestamptz' },
    sent_at: { type: 'timestamptz' },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
    updated_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  });

  pgm.createIndex('notifications', 'user_id');
  pgm.createIndex('notifications', 'status');
  pgm.createIndex('notifications', ['user_id', 'is_read']);
  pgm.createIndex('notifications', 'created_at');
  pgm.createIndex('notifications', 'source_event_id', { where: 'source_event_id IS NOT NULL' });
};

exports.down = (pgm) => {
  pgm.dropTable('notifications');
  pgm.dropTable('notification_templates');
  pgm.dropType('notification_status');
  pgm.dropType('notification_channel');
};
