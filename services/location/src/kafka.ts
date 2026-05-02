import { Kafka, type Producer, type Consumer } from 'kafkajs';
import { config } from './config.js';

const kafka = new Kafka({
  clientId: config.SERVICE_NAME,
  brokers: config.KAFKA_BROKERS.split(','),
});

let _producer: Producer | null = null;
let _consumer: Consumer | null = null;

export async function getProducer(): Promise<Producer> {
  if (!_producer) { _producer = kafka.producer(); await _producer.connect(); }
  return _producer;
}

export async function getConsumer(groupId: string): Promise<Consumer> {
  if (!_consumer) { _consumer = kafka.consumer({ groupId }); await _consumer.connect(); }
  return _consumer;
}

export async function disconnectAll(): Promise<void> {
  await _producer?.disconnect();
  await _consumer?.disconnect();
}
