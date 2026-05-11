/** @type {import('node-pg-migrate').MigrationBuilder} */
exports.up = (pgm) => {
  pgm.sql(`CREATE EXTENSION IF NOT EXISTS postgis`);

  pgm.sql(`ALTER TYPE route_status ADD VALUE IF NOT EXISTS 'departed'`);

  pgm.sql(`ALTER TABLE routes ADD COLUMN IF NOT EXISTS flexibility_minutes INTEGER NOT NULL DEFAULT 15`);

  pgm.sql(`ALTER TABLE routes ADD COLUMN IF NOT EXISTS route_geometry GEOGRAPHY(LineString, 4326)`);

  // Backfill from Google-encoded polyline where available
  pgm.sql(`
    UPDATE routes
    SET route_geometry = ST_LineFromEncodedPolyline(polyline)::geography
    WHERE polyline IS NOT NULL AND route_geometry IS NULL
  `);

  // Fallback: straight line between origin and destination
  pgm.sql(`
    UPDATE routes
    SET route_geometry = ST_MakeLine(
      ST_SetSRID(ST_MakePoint(origin_lng::double precision, origin_lat::double precision), 4326),
      ST_SetSRID(ST_MakePoint(destination_lng::double precision, destination_lat::double precision), 4326)
    )::geography
    WHERE route_geometry IS NULL
  `);

  pgm.sql(`CREATE INDEX IF NOT EXISTS idx_routes_geometry ON routes USING GIST (route_geometry)`);

  pgm.sql(`
    CREATE INDEX IF NOT EXISTS idx_routes_active
    ON routes (status, available_seats)
    WHERE status = 'active' AND available_seats > 0
  `);
};

exports.down = (pgm) => {
  pgm.sql(`DROP INDEX IF EXISTS idx_routes_active`);
  pgm.sql(`DROP INDEX IF EXISTS idx_routes_geometry`);
  pgm.sql(`ALTER TABLE routes DROP COLUMN IF EXISTS route_geometry`);
  pgm.sql(`ALTER TABLE routes DROP COLUMN IF EXISTS flexibility_minutes`);
  // Note: cannot remove enum values in Postgres; departed stays in route_status
};
