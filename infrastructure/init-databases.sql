-- =================================================================
-- RISHFY PLATFORM - DATABASE BOOTSTRAP SCRIPT
-- =================================================================
-- This script is executed once by the local Postgres container on an
-- empty data volume. It creates one database/user pair per service and
-- leaves service-owned schemas to versioned migrations under
-- services/<service>/migrations.
-- =================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------
-- Service roles. Passwords mirror docker-compose.yml dev defaults.
-- Rotate via managed secrets outside local development.
-- -----------------------------------------------------------------
SELECT 'CREATE USER auth_user WITH PASSWORD ''dev_auth_password'''
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'auth_user')\gexec
SELECT 'CREATE USER user_user WITH PASSWORD ''dev_user_password'''
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'user_user')\gexec
SELECT 'CREATE USER route_user WITH PASSWORD ''dev_route_password'''
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'route_user')\gexec
SELECT 'CREATE USER booking_user WITH PASSWORD ''dev_booking_password'''
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'booking_user')\gexec
SELECT 'CREATE USER payment_user WITH PASSWORD ''dev_payment_password'''
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'payment_user')\gexec
SELECT 'CREATE USER location_user WITH PASSWORD ''dev_location_password'''
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'location_user')\gexec
SELECT 'CREATE USER notification_user WITH PASSWORD ''dev_notification_password'''
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'notification_user')\gexec

-- -----------------------------------------------------------------
-- Logical databases. CREATE DATABASE cannot run inside a transaction,
-- so use psql \gexec to keep the script idempotent for manual reruns.
-- -----------------------------------------------------------------
SELECT 'CREATE DATABASE auth_db OWNER auth_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'auth_db')\gexec
SELECT 'CREATE DATABASE user_db OWNER user_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'user_db')\gexec
SELECT 'CREATE DATABASE route_db OWNER route_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'route_db')\gexec
SELECT 'CREATE DATABASE booking_db OWNER booking_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'booking_db')\gexec
SELECT 'CREATE DATABASE payment_db OWNER payment_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'payment_db')\gexec
SELECT 'CREATE DATABASE location_db OWNER location_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'location_db')\gexec
SELECT 'CREATE DATABASE notification_db OWNER notification_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'notification_db')\gexec

-- -----------------------------------------------------------------
-- Baseline privileges for migration tools and service runtimes.
-- -----------------------------------------------------------------
\c auth_db
GRANT ALL PRIVILEGES ON DATABASE auth_db TO auth_user;
GRANT ALL ON SCHEMA public TO auth_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO auth_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO auth_user;

\c user_db
GRANT ALL PRIVILEGES ON DATABASE user_db TO user_user;
GRANT ALL ON SCHEMA public TO user_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO user_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO user_user;

\c route_db
GRANT ALL PRIVILEGES ON DATABASE route_db TO route_user;
GRANT ALL ON SCHEMA public TO route_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO route_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO route_user;

\c booking_db
GRANT ALL PRIVILEGES ON DATABASE booking_db TO booking_user;
GRANT ALL ON SCHEMA public TO booking_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO booking_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO booking_user;

\c payment_db
GRANT ALL PRIVILEGES ON DATABASE payment_db TO payment_user;
GRANT ALL ON SCHEMA public TO payment_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO payment_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO payment_user;

\c location_db
GRANT ALL PRIVILEGES ON DATABASE location_db TO location_user;
GRANT ALL ON SCHEMA public TO location_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO location_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO location_user;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS postgis;

\c notification_db
GRANT ALL PRIVILEGES ON DATABASE notification_db TO notification_user;
GRANT ALL ON SCHEMA public TO notification_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO notification_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO notification_user;

-- =================================================================
-- BOOTSTRAP COMPLETE
-- =================================================================
