import {
  Kafka,
  type Consumer,
  type ConsumerConfig,
  type EachMessagePayload,
  type KafkaConfig,
  type Producer,
  type ProducerConfig,
  type RecordMetadata,
} from 'kafkajs';
import type { Logger } from 'pino';

export interface CreateKafkaClientOptions {
  brokers: string[];
  clientId: string;
  ssl?: KafkaConfig['ssl'];
  sasl?: KafkaConfig['sasl'];
  logger?: Logger;
}

export interface PublishJsonMessageOptions<TValue> {
  producer: Producer;
  topic: string;
  key?: string;
  value: TValue;
  headers?: Record<string, string>;
}

export interface StartJsonConsumerOptions<TValue> {
  consumer: Consumer;
  topic: string;
  logger?: Logger;
  onMessage: (payload: {
    topic: string;
    partition: number;
    key?: string;
    value: TValue;
    raw: EachMessagePayload;
  }) => Promise<void>;
}

export function createKafkaClient(options: CreateKafkaClientOptions): Kafka {
  return new Kafka({
    clientId: options.clientId,
    brokers: options.brokers,
    ssl: options.ssl,
    sasl: options.sasl,
    logCreator: () => ({ log }) => {
      options.logger?.debug({ kafkaLog: log }, 'Kafka client log');
    },
  });
}

export function createKafkaProducer(kafka: Kafka, config?: ProducerConfig): Producer {
  return kafka.producer(config);
}

export function createKafkaConsumer(kafka: Kafka, config: ConsumerConfig): Consumer {
  return kafka.consumer(config);
}

export async function publishJsonMessage<TValue>(
  options: PublishJsonMessageOptions<TValue>
): Promise<RecordMetadata[]> {
  return options.producer.send({
    topic: options.topic,
    messages: [
      {
        key: options.key,
        value: JSON.stringify(options.value),
        headers: options.headers,
      },
    ],
  });
}

export async function startJsonConsumer<TValue>(
  options: StartJsonConsumerOptions<TValue>
): Promise<void> {
  await options.consumer.subscribe({ topic: options.topic, fromBeginning: false });
  await options.consumer.run({
    eachMessage: async (raw) => {
      const valueBuffer = raw.message.value;
      if (!valueBuffer) {
        options.logger?.warn({ topic: raw.topic, partition: raw.partition }, 'Kafka message missing payload');
        return;
      }

      const parsedValue = JSON.parse(valueBuffer.toString()) as TValue;
      await options.onMessage({
        topic: raw.topic,
        partition: raw.partition,
        key: raw.message.key?.toString(),
        value: parsedValue,
        raw,
      });
    },
  });
}

export async function connectKafkaProducer(producer: Producer): Promise<void> {
  await producer.connect();
}

export async function disconnectKafkaProducer(producer: Producer): Promise<void> {
  await producer.disconnect();
}

export async function connectKafkaConsumer(consumer: Consumer): Promise<void> {
  await consumer.connect();
}

export async function disconnectKafkaConsumer(consumer: Consumer): Promise<void> {
  await consumer.disconnect();
}
