-- =================================================================
-- RISHFY PLATFORM - DATABASE INITIALIZATION SCRIPT
-- =================================================================
-- This script creates all logical databases and their schemas.
-- Run as a PostgreSQL superuser.
--
-- Usage: psql -U postgres -f init-databases.sql
-- =================================================================

-- =================================================================
-- CREATE DATABASES AND USERS
-- =================================================================

-- Create service users (one per service for isolation)
CREATE USER auth_service WITH PASSWORD 'CHANGE_ME_auth_pwd';
CREATE USER user_service WITH PASSWORD 'CHANGE_ME_user_pwd';
CREATE USER route_service WITH PASSWORD 'CHANGE_ME_route_pwd';
CREATE USER booking_service WITH PASSWORD 'CHANGE_ME_booking_pwd';
CREATE USER payment_service WITH PASSWORD 'CHANGE_ME_payment_pwd';
CREATE USER location_service WITH PASSWORD 'CHANGE_ME_location_pwd';
CREATE USER notification_service WITH PASSWORD 'CHANGE_ME_notification_pwd';

-- Create databases
CREATE DATABASE auth_db OWNER auth_service;
CREATE DATABASE user_db OWNER user_service;
CREATE DATABASE route_db OWNER route_service;
CREATE DATABASE booking_db OWNER booking_service;
CREATE DATABASE payment_db OWNER payment_service;
CREATE DATABASE location_db OWNER location_service;
CREATE DATABASE notification_db OWNER notification_service;

-- =================================================================
-- AUTH_DB SCHEMA
-- =================================================================
\c auth_db auth_service

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- auth_users table
CREATE TABLE auth_users (
    id                 SERIAL PRIMARY KEY,
    phone              VARCHAR(20) UNIQUE NOT NULL,
    email              VARCHAR(255) UNIQUE,
    password_hash      VARCHAR(255) NOT NULL,
    user_type          VARCHAR(20) NOT NULL CHECK (user_type IN ('driver', 'rider', 'admin')),
    verified           BOOLEAN NOT NULL DEFAULT FALSE,
    status             VARCHAR(20) NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active', 'suspended', 'banned', 'deleted')),
    last_login_at      TIMESTAMPTZ,
    failed_login_count INTEGER NOT NULL DEFAULT 0,
    locked_until       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_auth_users_phone ON auth_users(phone);
CREATE INDEX idx_auth_users_email ON auth_users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_auth_users_type_status ON auth_users(user_type, status);

CREATE TRIGGER trg_auth_users_updated_at
    BEFORE UPDATE ON auth_users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- verification_codes table
CREATE TABLE verification_codes (
    id           SERIAL PRIMARY KEY,
    user_id      INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    code         VARCHAR(6) NOT NULL,
    type         VARCHAR(30) NOT NULL
                 CHECK (type IN ('registration', 'login', 'password_reset', 'phone_change')),
    attempts     INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3,
    expires_at   TIMESTAMPTZ NOT NULL,
    used         BOOLEAN NOT NULL DEFAULT FALSE,
    used_at      TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verification_codes_user_type ON verification_codes(user_id, type)
    WHERE used = FALSE;
CREATE INDEX idx_verification_codes_expires ON verification_codes(expires_at)
    WHERE used = FALSE;

-- refresh_tokens table
CREATE TABLE refresh_tokens (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    token_hash     VARCHAR(255) UNIQUE NOT NULL,
    device_info    JSONB,
    expires_at     TIMESTAMPTZ NOT NULL,
    revoked        BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at     TIMESTAMPTZ,
    revoked_reason VARCHAR(100),
    last_used_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id) WHERE revoked = FALSE;
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at) WHERE revoked = FALSE;

-- password_resets table
CREATE TABLE password_resets (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used       BOOLEAN NOT NULL DEFAULT FALSE,
    used_at    TIMESTAMPTZ,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_password_resets_user ON password_resets(user_id) WHERE used = FALSE;

-- =================================================================
-- USER_DB SCHEMA
-- =================================================================
\c user_db user_service

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- users table
CREATE TABLE users (
    id                       SERIAL PRIMARY KEY,
    auth_id                  INTEGER UNIQUE NOT NULL,
    first_name               VARCHAR(100) NOT NULL,
    last_name                VARCHAR(100) NOT NULL,
    profile_picture_url      TEXT,
    date_of_birth            DATE,
    gender                   VARCHAR(10) CHECK (gender IN ('male', 'female', 'other', 'prefer_not_to_say')),
    national_id              VARCHAR(50),
    phone                    VARCHAR(20) NOT NULL,
    email                    VARCHAR(255),
    preferred_language       VARCHAR(10) NOT NULL DEFAULT 'en' CHECK (preferred_language IN ('en', 'sw')),
    preferred_payment_method VARCHAR(50),
    notification_preferences JSONB NOT NULL DEFAULT '{"push": true, "sms": true, "email": false}',
    emergency_contact_name   VARCHAR(100),
    emergency_contact_phone  VARCHAR(20),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at               TIMESTAMPTZ
);

CREATE INDEX idx_users_auth ON users(auth_id);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_deleted ON users(deleted_at) WHERE deleted_at IS NULL;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- driver_profiles table
CREATE TABLE driver_profiles (
    id                      SERIAL PRIMARY KEY,
    user_id                 INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    license_number          VARCHAR(50) UNIQUE NOT NULL,
    license_expiry          DATE NOT NULL,
    license_verified        BOOLEAN NOT NULL DEFAULT FALSE,
    license_photo_url       TEXT,
    license_verified_at     TIMESTAMPTZ,
    latra_license_number    VARCHAR(50),
    latra_verified          BOOLEAN NOT NULL DEFAULT FALSE,
    latra_verification_date TIMESTAMPTZ,
    latra_license_expiry    DATE,
    active_vehicle_id       INTEGER,
    status                  VARCHAR(20) NOT NULL DEFAULT 'offline'
                            CHECK (status IN ('online', 'offline', 'busy', 'suspended')),
    total_routes_posted     INTEGER NOT NULL DEFAULT 0,
    completed_trips         INTEGER NOT NULL DEFAULT 0,
    cancelled_trips         INTEGER NOT NULL DEFAULT 0,
    rating_sum              INTEGER NOT NULL DEFAULT 0,
    rating_count            INTEGER NOT NULL DEFAULT 0,
    rating_avg              DECIMAL(3,2) NOT NULL DEFAULT 5.00
                            CHECK (rating_avg >= 0 AND rating_avg <= 5),
    acceptance_rate         DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    cancellation_rate       DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    response_time_avg_sec   INTEGER,
    total_earnings_tzs      DECIMAL(12,2) NOT NULL DEFAULT 0,
    pending_payout_tzs      DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_driver_profiles_status ON driver_profiles(status) WHERE status != 'suspended';
CREATE INDEX idx_driver_profiles_latra ON driver_profiles(latra_verified) WHERE latra_verified = TRUE;
CREATE INDEX idx_driver_profiles_rating ON driver_profiles(rating_avg DESC);

CREATE TRIGGER trg_driver_profiles_updated_at
    BEFORE UPDATE ON driver_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- vehicles table
CREATE TABLE vehicles (
    id                      SERIAL PRIMARY KEY,
    driver_id               INTEGER NOT NULL REFERENCES driver_profiles(id) ON DELETE CASCADE,
    registration_number     VARCHAR(20) UNIQUE NOT NULL,
    make                    VARCHAR(50) NOT NULL,
    model                   VARCHAR(50) NOT NULL,
    year                    INTEGER NOT NULL CHECK (year >= 1990 AND year <= 2030),
    color                   VARCHAR(30) NOT NULL,
    capacity                INTEGER NOT NULL CHECK (capacity >= 1 AND capacity <= 20),
    vehicle_type            VARCHAR(30) NOT NULL
                            CHECK (vehicle_type IN ('sedan', 'suv', 'van', 'hatchback', 'pickup', 'minibus')),
    latra_license_number    VARCHAR(50),
    latra_verified          BOOLEAN NOT NULL DEFAULT FALSE,
    latra_license_expiry    DATE,
    latra_verified_at       TIMESTAMPTZ,
    insurance_company       VARCHAR(100),
    insurance_policy_number VARCHAR(100),
    insurance_expiry        DATE,
    inspection_expiry       DATE,
    photos                  JSONB NOT NULL DEFAULT '[]',
    active                  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE driver_profiles
    ADD CONSTRAINT fk_driver_active_vehicle
    FOREIGN KEY (active_vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL;

CREATE INDEX idx_vehicles_driver ON vehicles(driver_id);
CREATE INDEX idx_vehicles_registration ON vehicles(registration_number);
CREATE INDEX idx_vehicles_latra ON vehicles(latra_verified) WHERE latra_verified = TRUE;

CREATE TRIGGER trg_vehicles_updated_at
    BEFORE UPDATE ON vehicles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- user_devices table
CREATE TABLE user_devices (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id      VARCHAR(255) NOT NULL,
    platform       VARCHAR(20) NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    fcm_token      TEXT,
    app_version    VARCHAR(20),
    os_version     VARCHAR(20),
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);

CREATE INDEX idx_user_devices_user ON user_devices(user_id);
CREATE INDEX idx_user_devices_fcm ON user_devices(fcm_token) WHERE fcm_token IS NOT NULL;

-- =================================================================
-- ROUTE_DB SCHEMA
-- =================================================================
\c route_db route_service

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- routes table
CREATE TABLE routes (
    id                   SERIAL PRIMARY KEY,
    driver_id            INTEGER NOT NULL,
    origin_name          VARCHAR(255) NOT NULL,
    origin_lat           DECIMAL(10, 8) NOT NULL CHECK (origin_lat >= -90 AND origin_lat <= 90),
    origin_lng           DECIMAL(11, 8) NOT NULL CHECK (origin_lng >= -180 AND origin_lng <= 180),
    origin_point         GEOGRAPHY(POINT, 4326),
    origin_place_id      VARCHAR(255),
    destination_name     VARCHAR(255) NOT NULL,
    destination_lat      DECIMAL(10, 8) NOT NULL CHECK (destination_lat >= -90 AND destination_lat <= 90),
    destination_lng      DECIMAL(11, 8) NOT NULL CHECK (destination_lng >= -180 AND destination_lng <= 180),
    destination_point    GEOGRAPHY(POINT, 4326),
    destination_place_id VARCHAR(255),
    departure_time       TIMESTAMPTZ NOT NULL,
    estimated_arrival    TIMESTAMPTZ,
    total_seats          INTEGER NOT NULL CHECK (total_seats >= 1 AND total_seats <= 20),
    available_seats      INTEGER NOT NULL CHECK (available_seats >= 0),
    price_per_seat       DECIMAL(10, 2) NOT NULL CHECK (price_per_seat > 0),
    currency             VARCHAR(3) NOT NULL DEFAULT 'TZS',
    distance_km          DECIMAL(10, 2),
    duration_minutes     INTEGER,
    route_polyline       TEXT,
    route_type           VARCHAR(20) NOT NULL DEFAULT 'one-time'
                         CHECK (route_type IN ('one-time', 'recurring')),
    recurrence_pattern   JSONB,
    parent_route_id      INTEGER REFERENCES routes(id) ON DELETE SET NULL,
    status               VARCHAR(20) NOT NULL DEFAULT 'scheduled'
                         CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled', 'expired')),
    notes                TEXT,
    preferences          JSONB NOT NULL DEFAULT '{}',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_seats_available CHECK (available_seats <= total_seats),
    CONSTRAINT chk_times CHECK (estimated_arrival IS NULL OR estimated_arrival > departure_time)
);

CREATE OR REPLACE FUNCTION update_route_geography()
RETURNS TRIGGER AS $$
BEGIN
    NEW.origin_point = ST_SetSRID(ST_MakePoint(NEW.origin_lng, NEW.origin_lat), 4326)::geography;
    NEW.destination_point = ST_SetSRID(ST_MakePoint(NEW.destination_lng, NEW.destination_lat), 4326)::geography;
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_routes_geography
    BEFORE INSERT OR UPDATE ON routes
    FOR EACH ROW
    EXECUTE FUNCTION update_route_geography();

CREATE INDEX idx_routes_driver ON routes(driver_id);
CREATE INDEX idx_routes_status ON routes(status);
CREATE INDEX idx_routes_departure ON routes(departure_time)
    WHERE status IN ('scheduled', 'active');
CREATE INDEX idx_routes_available_seats ON routes(available_seats, departure_time)
    WHERE status = 'scheduled' AND available_seats > 0;
CREATE INDEX idx_routes_origin_geom ON routes USING GIST(origin_point);
CREATE INDEX idx_routes_destination_geom ON routes USING GIST(destination_point);
CREATE INDEX idx_routes_type ON routes(route_type, parent_route_id) WHERE route_type = 'recurring';

-- route_stops table
CREATE TABLE route_stops (
    id             SERIAL PRIMARY KEY,
    route_id       INTEGER NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    stop_order     INTEGER NOT NULL,
    stop_name      VARCHAR(255) NOT NULL,
    lat            DECIMAL(10, 8) NOT NULL,
    lng            DECIMAL(11, 8) NOT NULL,
    stop_point     GEOGRAPHY(POINT, 4326),
    estimated_time TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(route_id, stop_order)
);

CREATE INDEX idx_route_stops_route ON route_stops(route_id);
CREATE INDEX idx_route_stops_geom ON route_stops USING GIST(stop_point);

-- route_search_history table
CREATE TABLE route_search_history (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER,
    origin_lat      DECIMAL(10, 8) NOT NULL,
    origin_lng      DECIMAL(11, 8) NOT NULL,
    destination_lat DECIMAL(10, 8) NOT NULL,
    destination_lng DECIMAL(11, 8) NOT NULL,
    search_time     TIMESTAMPTZ NOT NULL,
    result_count    INTEGER NOT NULL DEFAULT 0,
    booked          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_search_history_time ON route_search_history(created_at);
CREATE INDEX idx_search_history_user ON route_search_history(user_id) WHERE user_id IS NOT NULL;

-- =================================================================
-- BOOKING_DB SCHEMA
-- =================================================================
\c booking_db booking_service

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- bookings table
CREATE TABLE bookings (
    id                  SERIAL PRIMARY KEY,
    route_id            INTEGER NOT NULL,
    passenger_id        INTEGER NOT NULL,
    seats_booked        INTEGER NOT NULL CHECK (seats_booked >= 1),
    pickup_lat          DECIMAL(10, 8) NOT NULL,
    pickup_lng          DECIMAL(11, 8) NOT NULL,
    pickup_address      TEXT NOT NULL,
    pickup_notes        TEXT,
    dropoff_lat         DECIMAL(10, 8) NOT NULL,
    dropoff_lng         DECIMAL(11, 8) NOT NULL,
    dropoff_address     TEXT NOT NULL,
    dropoff_notes       TEXT,
    price_per_seat      DECIMAL(10, 2) NOT NULL,
    total_amount        DECIMAL(10, 2) NOT NULL,
    platform_fee        DECIMAL(10, 2) NOT NULL,
    driver_earning      DECIMAL(10, 2) NOT NULL,
    currency            VARCHAR(3) NOT NULL DEFAULT 'TZS',
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'confirmed', 'active', 'completed', 'cancelled', 'no_show')),
    confirmation_code   VARCHAR(8) UNIQUE NOT NULL,
    cancellation_reason TEXT,
    cancelled_by        INTEGER,
    cancelled_at        TIMESTAMPTZ,
    cancellation_charge DECIMAL(10, 2) NOT NULL DEFAULT 0,
    refund_amount       DECIMAL(10, 2) NOT NULL DEFAULT 0,
    confirmed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_amounts CHECK (total_amount = price_per_seat * seats_booked),
    CONSTRAINT chk_fees CHECK (platform_fee + driver_earning = total_amount)
);

CREATE INDEX idx_bookings_route ON bookings(route_id);
CREATE INDEX idx_bookings_passenger ON bookings(passenger_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_confirmation ON bookings(confirmation_code);
CREATE INDEX idx_bookings_active ON bookings(route_id, status)
    WHERE status IN ('pending', 'confirmed', 'active');
CREATE INDEX idx_bookings_passenger_status ON bookings(passenger_id, status, created_at DESC);

CREATE TRIGGER trg_bookings_updated_at
    BEFORE UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- trips table
CREATE TABLE trips (
    id                      SERIAL PRIMARY KEY,
    booking_id              INTEGER UNIQUE NOT NULL REFERENCES bookings(id),
    route_id                INTEGER NOT NULL,
    driver_id               INTEGER NOT NULL,
    passenger_id            INTEGER NOT NULL,
    scheduled_start_time    TIMESTAMPTZ NOT NULL,
    actual_start_time       TIMESTAMPTZ,
    actual_end_time         TIMESTAMPTZ,
    start_lat               DECIMAL(10, 8),
    start_lng               DECIMAL(11, 8),
    end_lat                 DECIMAL(10, 8),
    end_lng                 DECIMAL(11, 8),
    actual_distance_km      DECIMAL(10, 2),
    actual_duration_minutes INTEGER,
    status                  VARCHAR(30) NOT NULL DEFAULT 'scheduled'
                            CHECK (status IN ('scheduled', 'driver_approaching', 'driver_arrived',
                                              'in_progress', 'completed', 'cancelled', 'disputed')),
    emergency_triggered     BOOLEAN NOT NULL DEFAULT FALSE,
    emergency_triggered_at  TIMESTAMPTZ,
    emergency_notes         TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trips_booking ON trips(booking_id);
CREATE INDEX idx_trips_driver_status ON trips(driver_id, status);
CREATE INDEX idx_trips_passenger_status ON trips(passenger_id, status);
CREATE INDEX idx_trips_status ON trips(status);
CREATE INDEX idx_trips_active ON trips(driver_id)
    WHERE status IN ('scheduled', 'driver_approaching', 'driver_arrived', 'in_progress');

CREATE TRIGGER trg_trips_updated_at
    BEFORE UPDATE ON trips
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ratings table
CREATE TABLE ratings (
    id           SERIAL PRIMARY KEY,
    trip_id      INTEGER NOT NULL REFERENCES trips(id),
    booking_id   INTEGER NOT NULL REFERENCES bookings(id),
    rater_id     INTEGER NOT NULL,
    rated_id     INTEGER NOT NULL,
    rater_type   VARCHAR(10) NOT NULL CHECK (rater_type IN ('driver', 'passenger')),
    rating_value INTEGER NOT NULL CHECK (rating_value >= 1 AND rating_value <= 5),
    comment      TEXT,
    tags         VARCHAR(50)[],
    visible      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(trip_id, rater_id)
);

CREATE INDEX idx_ratings_trip ON ratings(trip_id);
CREATE INDEX idx_ratings_rated ON ratings(rated_id, visible);
CREATE INDEX idx_ratings_created ON ratings(created_at);

-- booking_events table
CREATE TABLE booking_events (
    id         SERIAL PRIMARY KEY,
    booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    actor_id   INTEGER,
    actor_type VARCHAR(20),
    metadata   JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_booking_events_booking ON booking_events(booking_id, created_at DESC);
CREATE INDEX idx_booking_events_type ON booking_events(event_type);

-- =================================================================
-- PAYMENT_DB SCHEMA
-- =================================================================
\c payment_db payment_service

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- payments table
CREATE TABLE payments (
    id                    SERIAL PRIMARY KEY,
    booking_id            INTEGER NOT NULL,
    payer_id              INTEGER NOT NULL,
    amount                DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    currency              VARCHAR(3) NOT NULL DEFAULT 'TZS',
    payment_method        VARCHAR(50) NOT NULL
                          CHECK (payment_method IN ('m-pesa', 'tigopesa', 'airtel-money', 'cash', 'card')),
    phone_number          VARCHAR(20),
    transaction_reference VARCHAR(255) UNIQUE NOT NULL,
    external_reference    VARCHAR(255),
    idempotency_key       VARCHAR(255) UNIQUE NOT NULL,
    status                VARCHAR(20) NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded', 'partially_refunded', 'cancelled')),
    failure_reason        TEXT,
    failure_code          VARCHAR(50),
    metadata              JSONB,
    initiated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_at               TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_booking ON payments(booking_id);
CREATE INDEX idx_payments_payer ON payments(payer_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_reference ON payments(transaction_reference);
CREATE INDEX idx_payments_external_ref ON payments(external_reference) WHERE external_reference IS NOT NULL;
CREATE INDEX idx_payments_created ON payments(created_at DESC);

CREATE TRIGGER trg_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- payment_splits table
CREATE TABLE payment_splits (
    id                     SERIAL PRIMARY KEY,
    payment_id             INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    recipient_id           INTEGER,
    recipient_type         VARCHAR(20) NOT NULL
                           CHECK (recipient_type IN ('driver', 'platform', 'promotion')),
    amount                 DECIMAL(10, 2) NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'queued', 'disbursed', 'failed', 'cancelled')),
    disbursed_at           TIMESTAMPTZ,
    disbursement_reference VARCHAR(255),
    failure_reason         TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payment_splits_payment ON payment_splits(payment_id);
CREATE INDEX idx_payment_splits_recipient ON payment_splits(recipient_id, status);
CREATE INDEX idx_payment_splits_pending ON payment_splits(status, created_at)
    WHERE status IN ('pending', 'queued');

CREATE TRIGGER trg_payment_splits_updated_at
    BEFORE UPDATE ON payment_splits
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- refunds table
CREATE TABLE refunds (
    id               SERIAL PRIMARY KEY,
    payment_id       INTEGER NOT NULL REFERENCES payments(id),
    booking_id       INTEGER NOT NULL,
    amount           DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    reason           VARCHAR(255) NOT NULL,
    refund_type      VARCHAR(20) NOT NULL DEFAULT 'full'
                     CHECK (refund_type IN ('full', 'partial')),
    status           VARCHAR(20) NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    refund_reference VARCHAR(255),
    failure_reason   TEXT,
    initiated_by     INTEGER,
    processed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refunds_payment ON refunds(payment_id);
CREATE INDEX idx_refunds_booking ON refunds(booking_id);
CREATE INDEX idx_refunds_status ON refunds(status);

-- payment_webhooks table
CREATE TABLE payment_webhooks (
    id              SERIAL PRIMARY KEY,
    provider        VARCHAR(50) NOT NULL,
    external_id     VARCHAR(255) NOT NULL,
    payload         JSONB NOT NULL,
    signature       VARCHAR(500),
    verified        BOOLEAN NOT NULL DEFAULT FALSE,
    processed       BOOLEAN NOT NULL DEFAULT FALSE,
    processed_at    TIMESTAMPTZ,
    processing_error TEXT,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(provider, external_id)
);

CREATE INDEX idx_payment_webhooks_processed ON payment_webhooks(processed, received_at);

-- =================================================================
-- LOCATION_DB SCHEMA (TimescaleDB)
-- =================================================================
\c location_db location_service

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS postgis;

-- location_updates hypertable
CREATE TABLE location_updates (
    time        TIMESTAMPTZ NOT NULL,
    driver_id   INTEGER NOT NULL,
    trip_id     INTEGER,
    lat         DECIMAL(10, 8) NOT NULL,
    lng         DECIMAL(11, 8) NOT NULL,
    point       GEOGRAPHY(POINT, 4326),
    accuracy    FLOAT,
    bearing     FLOAT,
    speed       FLOAT,
    altitude    FLOAT,
    device_id   VARCHAR(100),
    app_version VARCHAR(20),
    PRIMARY KEY (driver_id, time)
);

SELECT create_hypertable('location_updates', 'time',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

SELECT add_retention_policy('location_updates', INTERVAL '90 days',
    if_not_exists => TRUE);

ALTER TABLE location_updates SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'driver_id'
);

SELECT add_compression_policy('location_updates', INTERVAL '7 days',
    if_not_exists => TRUE);

CREATE OR REPLACE FUNCTION update_location_geography()
RETURNS TRIGGER AS $$
BEGIN
    NEW.point = ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_location_geography
    BEFORE INSERT OR UPDATE ON location_updates
    FOR EACH ROW
    EXECUTE FUNCTION update_location_geography();

CREATE INDEX idx_location_driver_time ON location_updates (driver_id, time DESC);
CREATE INDEX idx_location_trip_time ON location_updates (trip_id, time DESC)
    WHERE trip_id IS NOT NULL;
CREATE INDEX idx_location_geom ON location_updates USING GIST(point);

-- driver_current_locations materialized view
CREATE MATERIALIZED VIEW driver_current_locations AS
SELECT DISTINCT ON (driver_id)
    driver_id,
    time AS last_update,
    lat,
    lng,
    point,
    bearing,
    speed
FROM location_updates
ORDER BY driver_id, time DESC;

CREATE UNIQUE INDEX idx_driver_current_locations_driver
    ON driver_current_locations(driver_id);
CREATE INDEX idx_driver_current_locations_geom
    ON driver_current_locations USING GIST(point);

-- trip_tracks table
CREATE TABLE trip_tracks (
    trip_id      INTEGER PRIMARY KEY,
    start_time   TIMESTAMPTZ NOT NULL,
    end_time     TIMESTAMPTZ NOT NULL,
    path         GEOGRAPHY(LINESTRING, 4326) NOT NULL,
    distance_km  DECIMAL(10, 2) NOT NULL,
    duration_sec INTEGER NOT NULL,
    point_count  INTEGER NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trip_tracks_time ON trip_tracks(start_time, end_time);
CREATE INDEX idx_trip_tracks_geom ON trip_tracks USING GIST(path);

-- =================================================================
-- NOTIFICATION_DB SCHEMA
-- =================================================================
\c notification_db notification_service

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- notifications table
CREATE TABLE notifications (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL,
    type       VARCHAR(50) NOT NULL,
    title      VARCHAR(255) NOT NULL,
    message    TEXT NOT NULL,
    data       JSONB,
    channels   VARCHAR(20)[] NOT NULL DEFAULT ARRAY['push'],
    read       BOOLEAN NOT NULL DEFAULT FALSE,
    read_at    TIMESTAMPTZ,
    priority   VARCHAR(10) NOT NULL DEFAULT 'normal'
               CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_unread ON notifications(user_id, created_at DESC)
    WHERE read = FALSE;
CREATE INDEX idx_notifications_user_all ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_type ON notifications(type, created_at);

-- notification_queue table
CREATE TABLE notification_queue (
    id                  SERIAL PRIMARY KEY,
    notification_id     INTEGER REFERENCES notifications(id) ON DELETE CASCADE,
    channel             VARCHAR(20) NOT NULL CHECK (channel IN ('push', 'sms', 'email', 'in_app')),
    recipient           VARCHAR(500) NOT NULL,
    payload             JSONB NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
    priority            INTEGER NOT NULL DEFAULT 5 CHECK (priority >= 1 AND priority <= 10),
    attempts            INTEGER NOT NULL DEFAULT 0,
    max_attempts        INTEGER NOT NULL DEFAULT 3,
    last_attempt_at     TIMESTAMPTZ,
    next_attempt_at     TIMESTAMPTZ,
    error_message       TEXT,
    provider            VARCHAR(50),
    provider_message_id VARCHAR(255),
    scheduled_for       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notification_queue_pending ON notification_queue(priority DESC, scheduled_for)
    WHERE status = 'pending';
CREATE INDEX idx_notification_queue_retry ON notification_queue(next_attempt_at)
    WHERE status = 'failed' AND attempts < max_attempts;
CREATE INDEX idx_notification_queue_notification ON notification_queue(notification_id);

-- notification_templates table
CREATE TABLE notification_templates (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    channel    VARCHAR(20) NOT NULL CHECK (channel IN ('push', 'sms', 'email')),
    language   VARCHAR(10) NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'sw')),
    subject    VARCHAR(255),
    template   TEXT NOT NULL,
    active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(name, channel, language)
);

CREATE TRIGGER trg_notification_templates_updated_at
    BEFORE UPDATE ON notification_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =================================================================
-- INITIALIZATION COMPLETE
-- =================================================================
-- All 7 databases created with schemas.
-- Remember to change default passwords in production!
-- =================================================================
