import type { Producer } from 'kafkajs';
import { publishJsonMessage } from '../kafka.js';

export interface RouteCancelledEvent {
  route_id: string;
  driver_id: string;
  departure_time: string;
  cancelled_at: string;
}

export async function publishRouteCancelled(producer: Producer, event: RouteCancelledEvent) {
  await publishJsonMessage({
    producer,
    topic: 'route.cancelled_by_driver',
    key: event.route_id,
    value: event,
  });
}
