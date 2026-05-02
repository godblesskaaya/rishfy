#!/usr/bin/env bash
# Idempotent Kafka topic creation — safe to run multiple times.
set -euo pipefail

BROKER="${KAFKA_BROKER:-localhost:9092}"
REPLICATION="${REPLICATION_FACTOR:-1}"
PARTITIONS="${PARTITIONS:-3}"

TOPICS=(
  "user.registered"
  "user.driver_upgraded"
  "user.rating_submitted"
  "route.created"
  "route.cancelled_by_driver"
  "booking.created"
  "booking.confirmed"
  "booking.cancelled"
  "booking.completed"
  "booking.expired"
  "booking.trip_started"
  "booking.trip_completed"
  "booking.rated"
  "payment.initiated"
  "payment.completed"
  "payment.failed"
  "payment.refunded"
  "notification.send"
  "driver.location_updated"
  "driver.arrived"
)

echo "Creating Kafka topics on broker: $BROKER"
for TOPIC in "${TOPICS[@]}"; do
  kafka-topics.sh \
    --bootstrap-server "$BROKER" \
    --create \
    --if-not-exists \
    --topic "$TOPIC" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION" \
    && echo "  OK: $TOPIC" || echo "  SKIP/ERR: $TOPIC"
done
echo "Done."
