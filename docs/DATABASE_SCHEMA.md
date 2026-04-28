# Rishfy Database Schema

> **Complete data model reference for all 7 services**
> Database: PostgreSQL 15 with PostGIS 3.x and TimescaleDB 2.x extensions

---

## Table of Contents

1. [Overview](#1-overview)
2. [Entity-Relationship Diagram (Master)](#2-entity-relationship-diagram-master)
3. [Database: auth_db](#3-database-auth_db)
4. [Database: user_db](#4-database-user_db)
5. [Database: route_db](#5-database-route_db)
6. [Database: booking_db](#6-database-booking_db)
7. [Database: payment_db](#7-database-payment_db)
8. [Database: location_db (TimescaleDB)](#8-database-location_db-timescaledb)
9. [Database: notification_db](#9-database-notification_db)
10. [Migration Strategy](#10-migration-strategy)
11. [Seed Data](#11-seed-data)
12. [Backup & Recovery](#12-backup--recovery)

---

## 1. Overview

### 1.1 Database-Per-Service Pattern

Each service owns a dedicated logical database. Physically, all databases run on a shared PostgreSQL cluster with logical separation enforced by:

- Separate database users per service
- No direct cross-database queries allowed
- Cross-service data via gRPC APIs only

### 1.2 Naming Conventions

| Convention | Rule | Example |
|------------|------|---------|
| Database names | `snake_case_db` | `auth_db`, `booking_db` |
| Table names | `snake_case_plural` | `users`, `routes`, `bookings` |
| Column names | `snake_case` | `first_name`, `created_at` |
| Primary keys | `id` (SERIAL) | `id SERIAL PRIMARY KEY` |
| Foreign keys | `{referenced_table_singular}_id` | `user_id`, `route_id` |
| Indexes | `idx_{table}_{column(s)}` | `idx_users_phone` |
| Unique constraints | `uq_{table}_{column(s)}` | `uq_users_email` |
| Timestamps | `created_at`, `updated_at` (TIMESTAMPTZ) | Always timezone-aware |

### 1.3 Common Patterns

**Every table includes:**
```sql
id SERIAL PRIMARY KEY,
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

**Soft delete pattern** (where applicable):
```sql
deleted_at TIMESTAMPTZ DEFAULT NULL
```

**Auto-update `updated_at`** (trigger on every table):
```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

---

## 2. Entity-Relationship Diagram (Master)

```mermaid
erDiagram
    auth_users ||--|| users : "auth_id (cross-DB)"
    users ||--o| driver_profiles : "is a driver"
    driver_profiles ||--o{ vehicles : "owns"
    driver_profiles ||--o{ routes : "posts (cross-DB)"
    routes ||--o{ bookings : "receives (cross-DB)"
    users ||--o{ bookings : "makes (cross-DB)"
    bookings ||--|| trips : "becomes"
    bookings ||--|| payments : "paid by (cross-DB)"
    payments ||--o{ payment_splits : "disbursed as"
    payments ||--o| refunds : "refunded"
    trips ||--o{ ratings : "rated"
    trips ||--o{ location_updates : "tracked (cross-DB)"
    users ||--o{ notifications : "receives (cross-DB)"

    auth_users {
        int id PK
        varchar phone UK
        varchar email UK
        varchar password_hash
        varchar user_type
        boolean verified
        varchar status
    }

    users {
        int id PK
        int auth_id UK "from auth_db"
        varchar first_name
        varchar last_name
        text profile_picture_url
        varchar phone
        varchar email
    }

    driver_profiles {
        int id PK
        int user_id FK
        varchar license_number UK
        boolean latra_verified
        decimal rating_avg
        varchar status
    }

    vehicles {
        int id PK
        int driver_id FK
        varchar registration_number UK
        int capacity
        boolean latra_verified
    }

    routes {
        int id PK
        int driver_id "from user_db"
        geography origin_point
        geography destination_point
        timestamp departure_time
        int available_seats
        decimal price_per_seat
        varchar status
    }

    bookings {
        int id PK
        int route_id "from route_db"
        int passenger_id "from user_db"
        int seats_booked
        decimal total_amount
        varchar status
        varchar confirmation_code UK
    }

    trips {
        int id PK
        int booking_id FK UK
        timestamp start_time
        timestamp end_time
        decimal actual_distance_km
        varchar status
    }

    payments {
        int id PK
        int booking_id "from booking_db"
        decimal amount
        varchar payment_method
        varchar transaction_reference UK
        varchar status
    }

    location_updates {
        timestamp time PK
        int driver_id PK
        int trip_id
        decimal lat
        decimal lng
        float speed
    }
```

---

## 3. Database: auth_db

**Owner**: Auth Service
**Purpose**: Authentication, tokens, verification codes
**Size Estimate**: Small (~5MB per 10k users)

### 3.1 Tables

#### `auth_users`

Minimal authentication data. Full profile lives in `user_db.users`.

```sql
CREATE TABLE auth_users (
    id                SERIAL PRIMARY KEY,
    phone             VARCHAR(20) UNIQUE NOT NULL,
    email             VARCHAR(255) UNIQUE,
    password_hash     VARCHAR(255) NOT NULL,
    user_type         VARCHAR(20) NOT NULL CHECK (user_type IN ('driver', 'rider', 'admin')),
    verified          BOOLEAN NOT NULL DEFAULT FALSE,
    status            VARCHAR(20) NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'suspended', 'banned', 'deleted')),
    last_login_at     TIMESTAMPTZ,
    failed_login_count INTEGER NOT NULL DEFAULT 0,
    locked_until      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_auth_users_phone ON auth_users(phone);
CREATE INDEX idx_auth_users_email ON auth_users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_auth_users_type_status ON auth_users(user_type, status);

COMMENT ON TABLE auth_users IS 'Minimal auth data; profile in user_db';
COMMENT ON COLUMN auth_users.failed_login_count IS 'Reset on successful login; triggers lockout at 5';
```

#### `verification_codes`

OTP codes for registration, login, password reset.

```sql
CREATE TABLE verification_codes (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    code          VARCHAR(6) NOT NULL,
    type          VARCHAR(30) NOT NULL
                  CHECK (type IN ('registration', 'login', 'password_reset', 'phone_change')),
    attempts      INTEGER NOT NULL DEFAULT 0,
    max_attempts  INTEGER NOT NULL DEFAULT 3,
    expires_at    TIMESTAMPTZ NOT NULL,
    used          BOOLEAN NOT NULL DEFAULT FALSE,
    used_at       TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verification_codes_user_type ON verification_codes(user_id, type)
    WHERE used = FALSE;
CREATE INDEX idx_verification_codes_expires ON verification_codes(expires_at)
    WHERE used = FALSE;

COMMENT ON TABLE verification_codes IS 'Short-lived OTP codes; cleaned up via cron';
```

#### `refresh_tokens`

Long-lived tokens for session refresh.

```sql
CREATE TABLE refresh_tokens (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) UNIQUE NOT NULL, -- SHA-256 hash, not the raw token
    device_info JSONB,  -- { device_id, user_agent, ip }
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at  TIMESTAMPTZ,
    revoked_reason VARCHAR(100),
    last_used_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id) WHERE revoked = FALSE;
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at) WHERE revoked = FALSE;

COMMENT ON COLUMN refresh_tokens.token_hash IS 'Store SHA-256 hash, not raw token';
```

#### `password_resets`

Password reset request tracking.

```sql
CREATE TABLE password_resets (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) UNIQUE NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    used        BOOLEAN NOT NULL DEFAULT FALSE,
    used_at     TIMESTAMPTZ,
    ip_address  INET,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_password_resets_user ON password_resets(user_id) WHERE used = FALSE;
```

### 3.2 Cleanup Jobs

```sql
-- Run daily via cron
-- Delete expired verification codes older than 7 days
DELETE FROM verification_codes
WHERE expires_at < NOW() - INTERVAL '7 days';

-- Delete expired refresh tokens
DELETE FROM refresh_tokens
WHERE expires_at < NOW() OR (revoked = TRUE AND revoked_at < NOW() - INTERVAL '30 days');
```

---

## 4. Database: user_db

**Owner**: User Service
**Purpose**: User profiles, driver profiles, vehicles
**Size Estimate**: Medium (~50MB per 10k users)

### 4.1 Tables

#### `users`

Full user profile data.

```sql
CREATE TABLE users (
    id                       SERIAL PRIMARY KEY,
    auth_id                  INTEGER UNIQUE NOT NULL, -- Foreign to auth_db.auth_users.id
    first_name               VARCHAR(100) NOT NULL,
    last_name                VARCHAR(100) NOT NULL,
    profile_picture_url      TEXT,
    date_of_birth            DATE,
    gender                   VARCHAR(10) CHECK (gender IN ('male', 'female', 'other', 'prefer_not_to_say')),
    national_id              VARCHAR(50),
    phone                    VARCHAR(20) NOT NULL,  -- Denormalized from auth_users
    email                    VARCHAR(255),          -- Denormalized from auth_users
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

COMMENT ON COLUMN users.auth_id IS 'References auth_db.auth_users.id (cross-DB)';
COMMENT ON COLUMN users.phone IS 'Denormalized for read efficiency';
```

#### `driver_profiles`

Extended profile for users who are drivers.

```sql
CREATE TABLE driver_profiles (
    id                      SERIAL PRIMARY KEY,
    user_id                 INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- License details
    license_number          VARCHAR(50) UNIQUE NOT NULL,
    license_expiry          DATE NOT NULL,
    license_verified        BOOLEAN NOT NULL DEFAULT FALSE,
    license_photo_url       TEXT,
    license_verified_at     TIMESTAMPTZ,

    -- LATRA details
    latra_license_number    VARCHAR(50),
    latra_verified          BOOLEAN NOT NULL DEFAULT FALSE,
    latra_verification_date TIMESTAMPTZ,
    latra_license_expiry    DATE,

    -- Active vehicle
    active_vehicle_id       INTEGER,  -- FK set after vehicles table

    -- Operational status
    status                  VARCHAR(20) NOT NULL DEFAULT 'offline'
                            CHECK (status IN ('online', 'offline', 'busy', 'suspended')),

    -- Performance metrics
    total_routes_posted     INTEGER NOT NULL DEFAULT 0,
    completed_trips         INTEGER NOT NULL DEFAULT 0,
    cancelled_trips         INTEGER NOT NULL DEFAULT 0,
    rating_sum              INTEGER NOT NULL DEFAULT 0,
    rating_count            INTEGER NOT NULL DEFAULT 0,
    rating_avg              DECIMAL(3,2) NOT NULL DEFAULT 5.00
                            CHECK (rating_avg >= 0 AND rating_avg <= 5),

    -- Behavioral metrics
    acceptance_rate         DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    cancellation_rate       DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    response_time_avg_sec   INTEGER,

    -- Earnings (cached totals)
    total_earnings_tzs      DECIMAL(12,2) NOT NULL DEFAULT 0,
    pending_payout_tzs      DECIMAL(12,2) NOT NULL DEFAULT 0,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_driver_profiles_status ON driver_profiles(status) WHERE status != 'suspended';
CREATE INDEX idx_driver_profiles_latra ON driver_profiles(latra_verified) WHERE latra_verified = TRUE;
CREATE INDEX idx_driver_profiles_rating ON driver_profiles(rating_avg DESC);

COMMENT ON COLUMN driver_profiles.status IS 'online=available for posting routes, busy=on active trip';
```

#### `vehicles`

Driver's registered vehicles.

```sql
CREATE TABLE vehicles (
    id                      SERIAL PRIMARY KEY,
    driver_id               INTEGER NOT NULL REFERENCES driver_profiles(id) ON DELETE CASCADE,

    -- Registration
    registration_number     VARCHAR(20) UNIQUE NOT NULL,
    make                    VARCHAR(50) NOT NULL,
    model                   VARCHAR(50) NOT NULL,
    year                    INTEGER NOT NULL CHECK (year >= 1990 AND year <= 2030),
    color                   VARCHAR(30) NOT NULL,
    capacity                INTEGER NOT NULL CHECK (capacity >= 1 AND capacity <= 20),
    vehicle_type            VARCHAR(30) NOT NULL
                            CHECK (vehicle_type IN ('sedan', 'suv', 'van', 'hatchback', 'pickup', 'minibus')),

    -- LATRA compliance
    latra_license_number    VARCHAR(50),
    latra_verified          BOOLEAN NOT NULL DEFAULT FALSE,
    latra_license_expiry    DATE,
    latra_verified_at       TIMESTAMPTZ,

    -- Documentation
    insurance_company       VARCHAR(100),
    insurance_policy_number VARCHAR(100),
    insurance_expiry        DATE,
    inspection_expiry       DATE,

    -- Media
    photos                  JSONB NOT NULL DEFAULT '[]',
                           -- [{"url": "...", "type": "front|back|side|interior"}]

    -- Status
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
```

#### `user_devices`

Registered devices for push notifications.

```sql
CREATE TABLE user_devices (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id       VARCHAR(255) NOT NULL,
    platform        VARCHAR(20) NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    fcm_token       TEXT,  -- Firebase Cloud Messaging token
    app_version     VARCHAR(20),
    os_version      VARCHAR(20),
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(user_id, device_id)
);

CREATE INDEX idx_user_devices_user ON user_devices(user_id);
CREATE INDEX idx_user_devices_fcm ON user_devices(fcm_token) WHERE fcm_token IS NOT NULL;
```

---

## 5. Database: route_db

**Owner**: Route Service
**Purpose**: Route posting, searching, matching
**Size Estimate**: Medium-Large (~200MB per 100k routes)
**Extensions**: PostGIS

### 5.1 Extensions Setup

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
```

### 5.2 Tables

#### `routes`

Posted routes by drivers.

```sql
CREATE TABLE routes (
    id                  SERIAL PRIMARY KEY,
    driver_id           INTEGER NOT NULL, -- References user_db.driver_profiles.id

    -- Origin
    origin_name         VARCHAR(255) NOT NULL,
    origin_lat          DECIMAL(10, 8) NOT NULL CHECK (origin_lat >= -90 AND origin_lat <= 90),
    origin_lng          DECIMAL(11, 8) NOT NULL CHECK (origin_lng >= -180 AND origin_lng <= 180),
    origin_point        GEOGRAPHY(POINT, 4326), -- Auto-populated via trigger
    origin_place_id     VARCHAR(255), -- Google Places ID

    -- Destination
    destination_name    VARCHAR(255) NOT NULL,
    destination_lat     DECIMAL(10, 8) NOT NULL CHECK (destination_lat >= -90 AND destination_lat <= 90),
    destination_lng     DECIMAL(11, 8) NOT NULL CHECK (destination_lng >= -180 AND destination_lng <= 180),
    destination_point   GEOGRAPHY(POINT, 4326),
    destination_place_id VARCHAR(255),

    -- Timing
    departure_time      TIMESTAMPTZ NOT NULL,
    estimated_arrival   TIMESTAMPTZ,

    -- Capacity & pricing
    total_seats         INTEGER NOT NULL CHECK (total_seats >= 1 AND total_seats <= 20),
    available_seats     INTEGER NOT NULL CHECK (available_seats >= 0),
    price_per_seat      DECIMAL(10, 2) NOT NULL CHECK (price_per_seat > 0),
    currency            VARCHAR(3) NOT NULL DEFAULT 'TZS',

    -- Route metadata
    distance_km         DECIMAL(10, 2),
    duration_minutes    INTEGER,
    route_polyline      TEXT, -- Google encoded polyline

    -- Recurrence
    route_type          VARCHAR(20) NOT NULL DEFAULT 'one-time'
                        CHECK (route_type IN ('one-time', 'recurring')),
    recurrence_pattern  JSONB, -- {"days": ["MON", "TUE"], "time": "08:00"}
    parent_route_id     INTEGER REFERENCES routes(id) ON DELETE SET NULL,

    -- Status
    status              VARCHAR(20) NOT NULL DEFAULT 'scheduled'
                        CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled', 'expired')),

    -- Preferences
    notes               TEXT,
    preferences         JSONB NOT NULL DEFAULT '{}',
                       -- {"music": true, "smoking": false, "pets": false, "luggage": true}

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_seats_available CHECK (available_seats <= total_seats),
    CONSTRAINT chk_times CHECK (estimated_arrival IS NULL OR estimated_arrival > departure_time)
);

-- Auto-populate geography points
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

-- Indexes
CREATE INDEX idx_routes_driver ON routes(driver_id);
CREATE INDEX idx_routes_status ON routes(status);
CREATE INDEX idx_routes_departure ON routes(departure_time)
    WHERE status IN ('scheduled', 'active');
CREATE INDEX idx_routes_available_seats ON routes(available_seats, departure_time)
    WHERE status = 'scheduled' AND available_seats > 0;
CREATE INDEX idx_routes_origin_geom ON routes USING GIST(origin_point);
CREATE INDEX idx_routes_destination_geom ON routes USING GIST(destination_point);
CREATE INDEX idx_routes_type ON routes(route_type, parent_route_id) WHERE route_type = 'recurring';

COMMENT ON COLUMN routes.driver_id IS 'References user_db.driver_profiles.id (cross-DB)';
```

#### `route_stops` (Optional intermediate stops)

```sql
CREATE TABLE route_stops (
    id              SERIAL PRIMARY KEY,
    route_id        INTEGER NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    stop_order      INTEGER NOT NULL,
    stop_name       VARCHAR(255) NOT NULL,
    lat             DECIMAL(10, 8) NOT NULL,
    lng             DECIMAL(11, 8) NOT NULL,
    stop_point      GEOGRAPHY(POINT, 4326),
    estimated_time  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(route_id, stop_order)
);

CREATE INDEX idx_route_stops_route ON route_stops(route_id);
CREATE INDEX idx_route_stops_geom ON route_stops USING GIST(stop_point);
```

#### `route_search_history`

Analytics for popular searches.

```sql
CREATE TABLE route_search_history (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER, -- Can be NULL for anonymous
    origin_lat          DECIMAL(10, 8) NOT NULL,
    origin_lng          DECIMAL(11, 8) NOT NULL,
    destination_lat     DECIMAL(10, 8) NOT NULL,
    destination_lng     DECIMAL(11, 8) NOT NULL,
    search_time         TIMESTAMPTZ NOT NULL,
    result_count        INTEGER NOT NULL DEFAULT 0,
    booked              BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_search_history_time ON route_search_history(created_at);
CREATE INDEX idx_search_history_user ON route_search_history(user_id) WHERE user_id IS NOT NULL;
```

---

## 6. Database: booking_db

**Owner**: Booking Service
**Purpose**: Reservations, trips, ratings
**Size Estimate**: Medium-Large (~500MB per 100k bookings)

### 6.1 Tables

#### `bookings`

Seat reservations.

```sql
CREATE TABLE bookings (
    id                  SERIAL PRIMARY KEY,
    route_id            INTEGER NOT NULL, -- References route_db.routes.id
    passenger_id        INTEGER NOT NULL, -- References user_db.users.id

    -- Booking details
    seats_booked        INTEGER NOT NULL CHECK (seats_booked >= 1),

    -- Pickup
    pickup_lat          DECIMAL(10, 8) NOT NULL,
    pickup_lng          DECIMAL(11, 8) NOT NULL,
    pickup_address      TEXT NOT NULL,
    pickup_notes        TEXT,

    -- Dropoff
    dropoff_lat         DECIMAL(10, 8) NOT NULL,
    dropoff_lng         DECIMAL(11, 8) NOT NULL,
    dropoff_address     TEXT NOT NULL,
    dropoff_notes       TEXT,

    -- Pricing (snapshot at booking time)
    price_per_seat      DECIMAL(10, 2) NOT NULL,
    total_amount        DECIMAL(10, 2) NOT NULL,
    platform_fee        DECIMAL(10, 2) NOT NULL,
    driver_earning      DECIMAL(10, 2) NOT NULL,
    currency            VARCHAR(3) NOT NULL DEFAULT 'TZS',

    -- Status lifecycle
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'confirmed', 'active', 'completed', 'cancelled', 'no_show')),
    confirmation_code   VARCHAR(8) UNIQUE NOT NULL, -- e.g., "A1B2C3D4"

    -- Cancellation
    cancellation_reason TEXT,
    cancelled_by        INTEGER, -- user_id who cancelled
    cancelled_at        TIMESTAMPTZ,
    cancellation_charge DECIMAL(10, 2) NOT NULL DEFAULT 0,
    refund_amount       DECIMAL(10, 2) NOT NULL DEFAULT 0,

    -- Timestamps
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
```

#### `trips`

Active/completed journeys (one trip per booking).

```sql
CREATE TABLE trips (
    id                      SERIAL PRIMARY KEY,
    booking_id              INTEGER UNIQUE NOT NULL REFERENCES bookings(id),
    route_id                INTEGER NOT NULL, -- Denormalized
    driver_id               INTEGER NOT NULL, -- Denormalized
    passenger_id            INTEGER NOT NULL, -- Denormalized

    -- Journey
    scheduled_start_time    TIMESTAMPTZ NOT NULL,
    actual_start_time       TIMESTAMPTZ,
    actual_end_time         TIMESTAMPTZ,

    -- Actual locations
    start_lat               DECIMAL(10, 8),
    start_lng               DECIMAL(11, 8),
    end_lat                 DECIMAL(10, 8),
    end_lng                 DECIMAL(11, 8),

    -- Metrics
    actual_distance_km      DECIMAL(10, 2),
    actual_duration_minutes INTEGER,

    -- Status
    status                  VARCHAR(30) NOT NULL DEFAULT 'scheduled'
                            CHECK (status IN ('scheduled', 'driver_approaching', 'driver_arrived',
                                              'in_progress', 'completed', 'cancelled', 'disputed')),

    -- Safety
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
```

#### `ratings`

Bidirectional ratings (driver↔passenger).

```sql
CREATE TABLE ratings (
    id              SERIAL PRIMARY KEY,
    trip_id         INTEGER NOT NULL REFERENCES trips(id),
    booking_id      INTEGER NOT NULL REFERENCES bookings(id),

    rater_id        INTEGER NOT NULL, -- user_id who gave rating
    rated_id        INTEGER NOT NULL, -- user_id who received rating
    rater_type      VARCHAR(10) NOT NULL CHECK (rater_type IN ('driver', 'passenger')),

    rating_value    INTEGER NOT NULL CHECK (rating_value >= 1 AND rating_value <= 5),
    comment         TEXT,
    tags            VARCHAR(50)[],
                    -- ['punctual', 'clean_car', 'friendly', 'safe_driver', 'quiet']

    visible         BOOLEAN NOT NULL DEFAULT TRUE, -- Can be hidden by admin
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(trip_id, rater_id) -- One rating per rater per trip
);

CREATE INDEX idx_ratings_trip ON ratings(trip_id);
CREATE INDEX idx_ratings_rated ON ratings(rated_id, visible);
CREATE INDEX idx_ratings_created ON ratings(created_at);
```

#### `booking_events`

Audit trail for booking lifecycle.

```sql
CREATE TABLE booking_events (
    id          SERIAL PRIMARY KEY,
    booking_id  INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    event_type  VARCHAR(50) NOT NULL,
                -- 'created', 'confirmed', 'driver_assigned', 'started',
                -- 'completed', 'cancelled', 'payment_received', 'refunded'
    actor_id    INTEGER,
    actor_type  VARCHAR(20),
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_booking_events_booking ON booking_events(booking_id, created_at DESC);
CREATE INDEX idx_booking_events_type ON booking_events(event_type);
```

---

## 7. Database: payment_db

**Owner**: Payment Service
**Purpose**: Payment processing, splits, refunds
**Size Estimate**: Medium (~200MB per 100k payments)

### 7.1 Tables

#### `payments`

Payment transactions.

```sql
CREATE TABLE payments (
    id                      SERIAL PRIMARY KEY,
    booking_id              INTEGER NOT NULL, -- References booking_db.bookings.id
    payer_id                INTEGER NOT NULL, -- References user_db.users.id

    -- Amount
    amount                  DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    currency                VARCHAR(3) NOT NULL DEFAULT 'TZS',

    -- Payment method
    payment_method          VARCHAR(50) NOT NULL
                            CHECK (payment_method IN ('m-pesa', 'tigopesa', 'airtel-money', 'cash', 'card')),
    phone_number            VARCHAR(20), -- For mobile money

    -- References
    transaction_reference   VARCHAR(255) UNIQUE NOT NULL, -- Our internal reference
    external_reference      VARCHAR(255), -- Provider's transaction ID (e.g., M-Pesa receipt)
    idempotency_key         VARCHAR(255) UNIQUE NOT NULL, -- Prevent duplicate charges

    -- Status
    status                  VARCHAR(20) NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded', 'partially_refunded', 'cancelled')),
    failure_reason          TEXT,
    failure_code            VARCHAR(50),

    -- Metadata (full provider response)
    metadata                JSONB,

    -- Timestamps
    initiated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_at                 TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_booking ON payments(booking_id);
CREATE INDEX idx_payments_payer ON payments(payer_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_reference ON payments(transaction_reference);
CREATE INDEX idx_payments_external_ref ON payments(external_reference) WHERE external_reference IS NOT NULL;
CREATE INDEX idx_payments_created ON payments(created_at DESC);
```

#### `payment_splits`

Breakdown of payment: driver earning + platform fee.

```sql
CREATE TABLE payment_splits (
    id                      SERIAL PRIMARY KEY,
    payment_id              INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,

    recipient_id            INTEGER, -- user_id (NULL for platform)
    recipient_type          VARCHAR(20) NOT NULL
                            CHECK (recipient_type IN ('driver', 'platform', 'promotion')),

    amount                  DECIMAL(10, 2) NOT NULL,

    status                  VARCHAR(20) NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'queued', 'disbursed', 'failed', 'cancelled')),

    disbursed_at            TIMESTAMPTZ,
    disbursement_reference  VARCHAR(255),
    failure_reason          TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payment_splits_payment ON payment_splits(payment_id);
CREATE INDEX idx_payment_splits_recipient ON payment_splits(recipient_id, status);
CREATE INDEX idx_payment_splits_pending ON payment_splits(status, created_at)
    WHERE status IN ('pending', 'queued');
```

#### `refunds`

Refund records.

```sql
CREATE TABLE refunds (
    id                  SERIAL PRIMARY KEY,
    payment_id          INTEGER NOT NULL REFERENCES payments(id),
    booking_id          INTEGER NOT NULL,

    amount              DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    reason              VARCHAR(255) NOT NULL,
    refund_type         VARCHAR(20) NOT NULL DEFAULT 'full'
                        CHECK (refund_type IN ('full', 'partial')),

    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    refund_reference    VARCHAR(255),
    failure_reason      TEXT,

    initiated_by        INTEGER, -- admin user_id or system
    processed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refunds_payment ON refunds(payment_id);
CREATE INDEX idx_refunds_booking ON refunds(booking_id);
CREATE INDEX idx_refunds_status ON refunds(status);
```

#### `payment_webhooks`

Incoming webhooks from payment providers (audit + idempotency).

```sql
CREATE TABLE payment_webhooks (
    id              SERIAL PRIMARY KEY,
    provider        VARCHAR(50) NOT NULL,
    external_id     VARCHAR(255) NOT NULL, -- Provider's event ID
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
```

---

## 8. Database: location_db (TimescaleDB)

**Owner**: Location Service
**Purpose**: Time-series GPS tracking
**Size Estimate**: Large (~10GB per 1000 active drivers over 90 days)
**Extensions**: TimescaleDB

### 8.1 Extensions Setup

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS postgis;
```

### 8.2 Tables

#### `location_updates` (Hypertable)

GPS location stream from drivers.

```sql
CREATE TABLE location_updates (
    time        TIMESTAMPTZ NOT NULL,
    driver_id   INTEGER NOT NULL,
    trip_id     INTEGER, -- NULL if not on active trip

    -- GPS data
    lat         DECIMAL(10, 8) NOT NULL,
    lng         DECIMAL(11, 8) NOT NULL,
    point       GEOGRAPHY(POINT, 4326),
    accuracy    FLOAT,    -- meters
    bearing     FLOAT,    -- 0-360 degrees
    speed       FLOAT,    -- m/s
    altitude    FLOAT,    -- meters

    -- Device info
    device_id   VARCHAR(100),
    app_version VARCHAR(20),

    PRIMARY KEY (driver_id, time)
);

-- Convert to hypertable (TimescaleDB optimization)
SELECT create_hypertable('location_updates', 'time',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

-- Retention policy: keep 90 days
SELECT add_retention_policy('location_updates', INTERVAL '90 days',
    if_not_exists => TRUE);

-- Compression policy: compress chunks older than 7 days
ALTER TABLE location_updates SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'driver_id'
);

SELECT add_compression_policy('location_updates', INTERVAL '7 days',
    if_not_exists => TRUE);

-- Auto-populate geography point
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

-- Indexes
CREATE INDEX idx_location_driver_time ON location_updates (driver_id, time DESC);
CREATE INDEX idx_location_trip_time ON location_updates (trip_id, time DESC)
    WHERE trip_id IS NOT NULL;
CREATE INDEX idx_location_geom ON location_updates USING GIST(point);
```

#### `driver_current_locations` (Materialized View)

Latest known location per driver.

```sql
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

-- Refresh every 30 seconds (via cron or pg_cron)
-- REFRESH MATERIALIZED VIEW CONCURRENTLY driver_current_locations;
```

**Note**: For real-time queries, use Redis GEOSPATIAL. Use this view for reporting/analytics.

#### `trip_tracks` (Completed trip paths)

Compressed trip paths for completed trips.

```sql
CREATE TABLE trip_tracks (
    trip_id         INTEGER PRIMARY KEY,
    start_time      TIMESTAMPTZ NOT NULL,
    end_time        TIMESTAMPTZ NOT NULL,
    path            GEOGRAPHY(LINESTRING, 4326) NOT NULL,
    distance_km     DECIMAL(10, 2) NOT NULL,
    duration_sec    INTEGER NOT NULL,
    point_count     INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trip_tracks_time ON trip_tracks(start_time, end_time);
CREATE INDEX idx_trip_tracks_geom ON trip_tracks USING GIST(path);

COMMENT ON TABLE trip_tracks IS 'Populated when trip completes; location_updates can be purged';
```

---

## 9. Database: notification_db

**Owner**: Notification Service
**Purpose**: Notification delivery queue
**Size Estimate**: Medium (~100MB per 100k notifications)

### 9.1 Tables

#### `notifications`

User-facing notifications.

```sql
CREATE TABLE notifications (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL, -- References user_db.users.id

    -- Content
    type        VARCHAR(50) NOT NULL,
                -- 'booking_confirmed', 'payment_received', 'driver_arrived', etc.
    title       VARCHAR(255) NOT NULL,
    message     TEXT NOT NULL,
    data        JSONB,  -- Deep-link data: {"booking_id": 123, "action": "view_booking"}

    -- Channels
    channels    VARCHAR(20)[] NOT NULL DEFAULT ARRAY['push'],
                -- ['push', 'sms', 'email', 'in_app']

    -- Status
    read        BOOLEAN NOT NULL DEFAULT FALSE,
    read_at     TIMESTAMPTZ,

    -- Priority
    priority    VARCHAR(10) NOT NULL DEFAULT 'normal'
                CHECK (priority IN ('low', 'normal', 'high', 'urgent')),

    expires_at  TIMESTAMPTZ, -- Optional expiration

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_unread ON notifications(user_id, created_at DESC)
    WHERE read = FALSE;
CREATE INDEX idx_notifications_user_all ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_type ON notifications(type, created_at);
```

#### `notification_queue`

Queue for delivery workers.

```sql
CREATE TABLE notification_queue (
    id                  SERIAL PRIMARY KEY,
    notification_id     INTEGER REFERENCES notifications(id) ON DELETE CASCADE,

    -- Channel
    channel             VARCHAR(20) NOT NULL CHECK (channel IN ('push', 'sms', 'email', 'in_app')),
    recipient           VARCHAR(500) NOT NULL, -- Phone, email, or FCM token
    payload             JSONB NOT NULL,

    -- Status
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
    priority            INTEGER NOT NULL DEFAULT 5 CHECK (priority >= 1 AND priority <= 10),
    attempts            INTEGER NOT NULL DEFAULT 0,
    max_attempts        INTEGER NOT NULL DEFAULT 3,
    last_attempt_at     TIMESTAMPTZ,
    next_attempt_at     TIMESTAMPTZ,
    error_message       TEXT,

    -- External tracking
    provider            VARCHAR(50),
    provider_message_id VARCHAR(255),

    scheduled_for       TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- Allow scheduled delivery
    sent_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notification_queue_pending ON notification_queue(priority DESC, scheduled_for)
    WHERE status = 'pending';
CREATE INDEX idx_notification_queue_retry ON notification_queue(next_attempt_at)
    WHERE status = 'failed' AND attempts < max_attempts;
CREATE INDEX idx_notification_queue_notification ON notification_queue(notification_id);
```

#### `notification_templates`

Reusable templates.

```sql
CREATE TABLE notification_templates (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(100) UNIQUE NOT NULL,
    channel         VARCHAR(20) NOT NULL CHECK (channel IN ('push', 'sms', 'email')),
    language        VARCHAR(10) NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'sw')),

    subject         VARCHAR(255), -- For email
    template        TEXT NOT NULL, -- With {{variables}}

    active          BOOLEAN NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(name, channel, language)
);
```

---

## 10. Migration Strategy

### 10.1 Bootstrap vs. migrations

`infrastructure/init-databases.sql` is intentionally limited to cluster bootstrap:

- creates one database/user pair per service (`auth_db`/`auth_user`, etc.)
- grants baseline privileges for service-owned schemas
- enables database-level extensions for `location_db`

Service tables are owned by versioned migrations under `services/<service>/migrations`. Do not add application tables directly to the bootstrap script.

### 10.2 Tool

Use **node-pg-migrate** for all service migrations. Each service package exposes the same commands:

```bash
cd services/auth
npm run migrate:up
npm run migrate:down
npm run migrate:create -- add-locked-until-to-auth-users
```

From the repository root, use the dev helper once Docker services are running:

```bash
./scripts/dev.sh migrate auth  # one service
./scripts/dev.sh migrate       # all services
```

### 10.3 Migration Files

Each service has its own `migrations/` directory. Sprint 1 ships the initial `auth_db` migration:

```
services/auth/migrations/
└── 1700000000001_initial_schema.js
```

The auth migration creates:

- `auth_users`
- `verification_codes`
- `refresh_tokens`
- `password_resets`
- indexes and the `updated_at` trigger function

### 10.4 Migration Template

```javascript
// migrations/TIMESTAMP_descriptive_name.js
exports.up = (pgm) => {
  pgm.createTable('example_table', {
    id: 'id',
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('NOW()') },
  });
};

exports.down = (pgm) => {
  pgm.dropTable('example_table');
};
```

### 10.5 Migration Rules

1. **Always reversible** (both `up` and `down` implemented)
2. **Never edit a merged migration** — create a new one
3. **Test migrations on staging first**
4. **Include comments** for non-obvious changes
5. **Separate schema and data migrations**
6. **Use transactions** where possible

---

## 11. Seed Data

### 11.1 Development Seeds

Development seeds live in `scripts/seeds/` and are run from the repository root:

```bash
npm run seed          # defaults to auth
bash scripts/seed.sh auth
```

Sprint 1 includes `scripts/seeds/01_admin_user.sql`, which seeds one verified admin identity into `auth_db.public.auth_users`. The script is idempotent via `ON CONFLICT (email) DO NOTHING`.

```sql
INSERT INTO auth_users (phone, email, password_hash, user_type, verified, status)
VALUES (
  '+255700000001',
  'admin@rishfy.co.tz',
  '$2b$10$...',
  'admin',
  TRUE,
  'active'
)
ON CONFLICT (email) DO NOTHING;
```

User-profile seed rows belong in a future user-service seed after `user_db` migrations are implemented.

### 11.2 Test Data Generators

Use **@faker-js/faker** for realistic test data.

```typescript
// scripts/seeds/generate-test-drivers.ts
import { faker } from '@faker-js/faker';

async function generateDrivers(count: number) {
    for (let i = 0; i < count; i++) {
        // Generate realistic Tanzanian driver profile
        const firstName = faker.person.firstName();
        const lastName = faker.person.lastName();
        const phone = `+25571${faker.string.numeric(7)}`;

        // ... insert into databases
    }
}
```

### 11.3 Seed Data Sets

| Set | Purpose | Count |
|-----|---------|-------|
| `admin` | Single admin user | 1 |
| `drivers-small` | Local development | 10 drivers, 10 vehicles |
| `drivers-medium` | Integration testing | 100 drivers, 100 vehicles |
| `passengers-small` | Local development | 50 passengers |
| `routes-small` | Local development | 20 routes (scheduled) |
| `bookings-small` | Local development | 10 bookings (various states) |

---

## 12. Backup & Recovery

### 12.1 Backup Strategy

| Type | Frequency | Retention | Location |
|------|-----------|-----------|----------|
| Full backup | Daily at 2 AM | 30 days | S3 + local |
| WAL archiving | Continuous | 7 days | S3 |
| Logical dump (per DB) | Daily | 30 days | S3 |
| Pre-migration snapshot | Before every migration | 7 days | Local |

### 12.2 Backup Commands

```bash
# Full cluster backup
pg_basebackup -h localhost -U replicator -D /backup/$(date +%Y%m%d) -Ft -z -P

# Logical dump per database
pg_dump -h localhost -U rishfy -d auth_db -F c -f /backup/auth_db_$(date +%Y%m%d).dump

# Restore from logical dump
pg_restore -h localhost -U rishfy -d auth_db -c /backup/auth_db_20260315.dump
```

### 12.3 Recovery Targets

- **RPO (Recovery Point Objective)**: < 5 minutes (WAL archiving)
- **RTO (Recovery Time Objective)**: < 30 minutes for critical databases

---

## Quick Reference

### Service-to-Database Mapping

| Service | Database | Extensions |
|---------|----------|------------|
| Auth | `auth_db` | - |
| User | `user_db` | - |
| Route | `route_db` | PostGIS |
| Booking | `booking_db` | - |
| Payment | `payment_db` | - |
| Location | `location_db` | PostGIS, TimescaleDB |
| Notification | `notification_db` | - |

### Cross-Database References (Foreign Keys Across Services)

| From | To | Enforcement |
|------|-----|------------|
| `user_db.users.auth_id` | `auth_db.auth_users.id` | Application-level |
| `route_db.routes.driver_id` | `user_db.driver_profiles.id` | Application-level |
| `booking_db.bookings.route_id` | `route_db.routes.id` | Application-level |
| `booking_db.bookings.passenger_id` | `user_db.users.id` | Application-level |
| `payment_db.payments.booking_id` | `booking_db.bookings.id` | Application-level |
| `location_db.location_updates.driver_id` | `user_db.driver_profiles.id` | Application-level |
| `notification_db.notifications.user_id` | `user_db.users.id` | Application-level |

**Note**: PostgreSQL foreign keys cannot span databases. Referential integrity enforced at application layer via API calls.

---

**Document Owner**: Backend Team
**Last Updated**: 2026-03-15
**Version**: 1.0
**Status**: Approved for Development
