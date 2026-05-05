import type { Consumer, Kafka } from 'kafkajs';
import type { Logger } from 'pino';
import type { UserRepository } from '../repositories/user.repository.js';
import {
  connectKafkaConsumer,
  createKafkaConsumer,
  startJsonConsumer,
} from '../kafka.js';
import { TOPIC_USER_REGISTERED, type UserRegisteredEvent } from '../events/user.events.js';

function normalizeRole(value: string | undefined): 'passenger' | 'driver' | 'admin' {
  if (value === 'driver' || value === 'admin') return value;
  return 'passenger';
}

function normalizeStatus(value: string | undefined): 'active' | 'suspended' | 'pending_verification' {
  if (value === 'suspended' || value === 'pending_verification') return value;
  return 'active';
}

function normalizePhone(event: UserRegisteredEvent): string | null {
  return event.phone_number ?? event.phone ?? null;
}

function normalizeFullName(event: UserRegisteredEvent): string {
  const name = event.full_name?.trim();
  return name && name.length > 0 ? name : 'Rishfy User';
}

export async function applyUserRegisteredEvent(
  repo: UserRepository,
  event: UserRegisteredEvent,
): Promise<void> {
  const phoneNumber = normalizePhone(event)?.trim();
  const fullName = normalizeFullName(event);

  if (!phoneNumber) {
    throw new Error('user.registered event missing phone_number');
  }

  await repo.upsertFromRegistration({
    id: event.user_id,
    phone_number: phoneNumber,
    full_name: fullName,
    email: event.email ?? null,
    role: normalizeRole(event.role ?? event.user_type),
    status: normalizeStatus(event.status),
  });
}

export async function startUserRegisteredConsumer(options: {
  kafka: Kafka;
  repo: UserRepository;
  logger?: Logger;
  groupId?: string;
}): Promise<Consumer> {
  const consumer = createKafkaConsumer(options.kafka, {
    groupId: options.groupId ?? 'user-service-registrations',
  });
  await connectKafkaConsumer(consumer);

  await startJsonConsumer<UserRegisteredEvent>({
    consumer,
    topic: TOPIC_USER_REGISTERED,
    logger: options.logger,
    onMessage: async ({ value }) => {
      await applyUserRegisteredEvent(options.repo, value);
      options.logger?.info({ user_id: value.user_id }, 'User profile synchronized from auth registration');
    },
  });

  return consumer;
}
