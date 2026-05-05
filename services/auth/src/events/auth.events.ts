import type { Producer } from 'kafkajs';

import { publishJsonMessage } from '../kafka.js';

const TOPIC_USER_REGISTERED = 'user.registered';

export interface UserRegisteredEvent {
  user_id: string;
  phone_number: string;
  full_name: string;
  role: string;
  created_at: string;
}

export async function publishUserRegistered(producer: Producer, event: UserRegisteredEvent) {
  await publishJsonMessage({
    producer,
    topic: TOPIC_USER_REGISTERED,
    key: event.user_id,
    value: event,
  });
}
