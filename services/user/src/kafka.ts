// Re-export kafka helpers — resolved from node_modules @rishfy/shared at runtime.
// During typecheck we resolve to the shared/core source via package.json exports.
export {
  createKafkaClient,
  createKafkaConsumer,
  createKafkaProducer,
  connectKafkaConsumer,
  connectKafkaProducer,
  publishJsonMessage,
  startJsonConsumer,
} from '@rishfy/shared/kafka';
