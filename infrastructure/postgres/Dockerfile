FROM postgres:16-bookworm

# Install PostGIS + TimescaleDB in a single layer so ca-certificates is
# available when curl fetches the TimescaleDB signing key.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    postgresql-16-postgis-3 \
    postgresql-16-postgis-3-scripts \
    ca-certificates \
    gnupg \
    curl \
 && curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/timescaledb.gpg \
 && printf 'deb [signed-by=/usr/share/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/debian/ bookworm main\n' \
    > /etc/apt/sources.list.d/timescaledb.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends timescaledb-2-postgresql-16 \
 && rm -rf /var/lib/apt/lists/*

# Enable TimescaleDB in the config template initialised with PGDATA
RUN echo "shared_preload_libraries = 'timescaledb'" \
    >> /usr/share/postgresql/16/postgresql.conf.sample
