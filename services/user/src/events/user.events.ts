import type { Producer } from 'kafkajs';
import { publishJsonMessage } from '../kafka.js';

const TOPIC_USER_REGISTERED = 'user.registered';
const TOPIC_USER_DRIVER_UPGRADED = 'user.driver_upgraded';
const TOPIC_RATING_SUBMITTED = 'rating.submitted';

export interface UserRegisteredEvent {
  user_id: string;
  phone_number: string;
  full_name: string;
  role: string;
  created_at: string;
}

export interface UserDriverUpgradedEvent {
  user_id: string;
  license_number: string;
  upgraded_at: string;
}

export interface RatingSubmittedEvent {
  ratee_id: string;
  rater_id: string;
  booking_id: string;
  score: number;
}

export async function publishUserRegistered(producer: Producer, event: UserRegisteredEvent) {
  await publishJsonMessage({
    producer,
    topic: TOPIC_USER_REGISTERED,
    key: event.user_id,
    value: event,
  });
}

export async function publishDriverUpgraded(producer: Producer, event: UserDriverUpgradedEvent) {
  await publishJsonMessage({
    producer,
    topic: TOPIC_USER_DRIVER_UPGRADED,
    key: event.user_id,
    value: event,
  });
}

export { TOPIC_RATING_SUBMITTED };
