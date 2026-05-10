# Rishfy Route Posting & Matching — Technical Specification

## 1. Core Principle

The driver's route is fixed. They are commuting regardless of whether any passenger books. Matching optimizes for the passenger — finding the driver whose existing route minimizes the passenger's effort to reach the vehicle. The driver does not detour; the passenger walks to and from the route.

---

## 2. Route Posting (Driver Flow)

### 2.1 Inputs

When a driver posts a route, the system captures:

| Field | Type | Description |
|---|---|---|
| Origin | lat/lng | Starting point of the commute |
| Destination | lat/lng | End point of the commute |
| Departure time | timestamp | When the driver leaves origin |
| Flexibility window | minutes | ± tolerance on departure time (e.g., ±15 min) |
| Recurrence | enum | One-time, daily, specific weekdays |
| Available seats | integer | Number of seats offered (1–4) |
| Route path | confirmed polyline | The actual road path (system-generated, driver-confirmed) |

### 2.2 Route Path Generation

1. The driver sets origin and destination on a map.
2. The system calls a routing API (Google Directions API or OSRM) to compute the optimal driving route.
3. The route is displayed on the map as a polyline.
4. The driver confirms the route, or adjusts it by adding/reordering waypoints (e.g., "I go through Sinza, not Mwenge").
5. The confirmed polyline is decoded into a PostGIS `geography(LineString, 4326)` and stored.
6. Polyline simplification (Douglas-Peucker algorithm) is applied to reduce point density while preserving route shape, balancing storage efficiency with matching accuracy.
7. The system also computes and stores the **total route duration** (from the routing API response) for use in temporal matching.

### 2.3 Route Status

A posted route can be in one of the following states:

- **Active** — visible to passengers, accepting bookings.
- **Full** — all seats booked; hidden from search results but retained for management.
- **Departed** — past the departure time + flexibility window; no longer matchable.
- **Cancelled** — driver withdrew the route.

For recurring routes, the system generates individual route instances per scheduled day, each independently trackable.

---

## 3. Passenger Search (Request)

### 3.1 Inputs

A passenger searching for a ride provides:

| Field | Type | Description |
|---|---|---|
| Pickup point | lat/lng | Where the passenger is or wants to be picked up |
| Dropoff point | lat/lng | Where the passenger wants to go |
| Desired departure time | timestamp | When they want to leave |
| Time flexibility | minutes | ± tolerance on departure (default: ±30 min) |
| Max walking distance | meters | Maximum acceptable walk to/from route (default: 1000m) |

### 3.2 What the Passenger Is Really Asking

"Find me a driver whose existing route passes close enough to where I am and where I'm going, heading in the right direction, at roughly the right time — and minimize how far I have to walk to get picked up."

---

## 4. Matching Algorithm

### 4.1 Pipeline Overview

The matching pipeline is a staged filter, moving from cheap/coarse operations to expensive/precise ones to minimize unnecessary computation.

```
Stage 1: Coarse Spatial Filter (PostGIS)
    ↓ candidates
Stage 2: Sequence Validation (PostGIS)
    ↓ directionally valid candidates
Stage 3: Temporal Filter (computation)
    ↓ time-aligned candidates
Stage 4: Precise Walking Distance (Routing API)
    ↓ walkable candidates
Stage 5: Ranking (walking distance to pickup)
    ↓ ordered results
```

### 4.2 Stage 1 — Coarse Spatial Filter

**Purpose:** Eliminate routes that are geometrically nowhere near the passenger's pickup or dropoff. This is a cheap PostGIS operation using spatial indexes.

**Method:** Find all active routes where the polyline passes within a generous straight-line radius of BOTH the pickup and dropoff points.

```sql
SELECT r.id, r.route_geometry, r.departure_time, r.duration_seconds
FROM routes r
WHERE r.status = 'active'
  AND r.available_seats > 0
  AND ST_DWithin(
        r.route_geometry,
        ST_SetSRID(ST_MakePoint(:pickup_lng, :pickup_lat), 4326)::geography,
        :coarse_radius  -- generous: e.g., 3000 meters
      )
  AND ST_DWithin(
        r.route_geometry,
        ST_SetSRID(ST_MakePoint(:dropoff_lng, :dropoff_lat), 4326)::geography,
        :coarse_radius
      );
```

**Notes:**
- The coarse radius (e.g., 3000m) is deliberately generous. It is NOT the passenger's walking tolerance — it exists only to reduce the candidate set before expensive operations.
- A GiST index on `route_geometry` makes this query performant even at scale.
- Routes with zero available seats or non-active status are excluded.

### 4.3 Stage 2 — Sequence Validation

**Purpose:** Ensure the driver passes near the pickup point BEFORE the dropoff point along their direction of travel.

**Method:** Project both points onto the route polyline and compare their linear positions.

```sql
SELECT *,
  ST_LineLocatePoint(route_geometry::geometry,
    ST_SetSRID(ST_MakePoint(:pickup_lng, :pickup_lat), 4326)) AS pickup_fraction,
  ST_LineLocatePoint(route_geometry::geometry,
    ST_SetSRID(ST_MakePoint(:dropoff_lng, :dropoff_lat), 4326)) AS dropoff_fraction
FROM (
  -- Stage 1 candidates
) candidates
WHERE pickup_fraction < dropoff_fraction;
```

**Explanation:**
- `ST_LineLocatePoint` returns a value between 0.0 (start of route) and 1.0 (end of route), representing where along the line a point projects.
- If `pickup_fraction >= dropoff_fraction`, the passenger would be traveling against the driver's direction — discard.

### 4.4 Stage 3 — Temporal Filter

**Purpose:** Ensure the driver will be near the pickup point at approximately the time the passenger wants to depart.

**Method:** Estimate when the driver will reach the pickup point using linear interpolation along the route.

```
estimated_pickup_time = driver_departure_time + (pickup_fraction × total_route_duration)
```

Filter to candidates where:

```
|estimated_pickup_time - passenger_desired_time| ≤ combined_flexibility
```

Where `combined_flexibility` accounts for both the driver's departure flexibility and the passenger's time tolerance.

**Limitation:** Linear interpolation assumes constant speed along the route. In reality, Dar es Salaam traffic is highly variable (Morogoro Road at rush hour vs. a residential area). This is acceptable for an MVP; future enhancement could use segment-level duration estimates from the routing API.

### 4.5 Stage 4 — Precise Walking Distance

**Purpose:** Replace the coarse straight-line distance with actual walking distance via the road network.

**Method:**

For each remaining candidate:

1. Compute the **closest point on the route polyline** to the passenger's pickup:
   ```sql
   ST_ClosestPoint(route_geometry::geometry,
     ST_SetSRID(ST_MakePoint(:pickup_lng, :pickup_lat), 4326))
   ```
2. Call a **walking directions API** (Google Directions API with `mode=walking`, or OSRM) from the passenger's pickup to that closest point.
3. The API returns **actual walking distance** (meters) and **walking time** (seconds).
4. Discard candidates where walking distance exceeds the passenger's `max_walking_distance`.
5. Repeat for the dropoff point (closest point on route to dropoff → actual walking distance to passenger's final destination).

**Cost management:**
- This stage involves external API calls per candidate, making it the most expensive stage.
- Stages 1–3 must aggressively reduce candidates so that Stage 4 processes only a small set (target: ≤10–15 candidates).
- Walking distance results should be **cached** using a geohash-based key (e.g., geohash of origin + geohash of destination at precision 7 ≈ 150m cells). This means a passenger searching from a location 100m away from a previous searcher can reuse the cached result.

### 4.6 Stage 5 — Ranking

**Purpose:** Order valid candidates by match quality for the passenger.

**Primary ranking signal:** Walking distance from passenger's pickup point to the nearest point on the driver's route (actual road distance, computed in Stage 4).

This is the sole ranking criterion for MVP. It directly reflects the passenger's core concern: "how far do I have to walk to get this ride?"

**Displayed to the passenger per result:**

| Field | Source |
|---|---|
| Walking distance to pickup | Stage 4 |
| Walking time to pickup | Stage 4 (routing API) |
| Suggested pickup point | Stage 4 (`ST_ClosestPoint` result, reverse-geocoded to a readable location name) |
| Walking distance from dropoff | Stage 4 (dropoff calculation) |
| Driver departure time | Route data |
| Estimated pickup time | Stage 3 calculation |
| Available seats | Route data |
| Driver name and photo | User data (LATRA-OR-03 compliance) |
| Vehicle details | Vehicle data (LATRA-OR-02 compliance) |

---

## 5. Booking Flow (Post-Match)

### 5.1 Automatic Booking

When a passenger selects a match:

1. The system creates a **booking record** linking the passenger to the route.
2. Available seats on the route are decremented by one.
3. The driver receives a **notification** with passenger details and the suggested pickup point along their route.
4. The driver can **decline** the booking within a defined window, which releases the seat and notifies the passenger.
5. If the driver does not decline, the booking is confirmed.

### 5.2 Driver's View of a Booking

The driver sees:

- Passenger name and photo
- Where along their route the passenger will be waiting (the suggested pickup point, shown on the route map)
- Where the passenger will exit (closest dropoff point on the route)
- Number of remaining available seats after this booking

The driver does NOT need to reroute or detour. The pickup and dropoff points are ON their existing route.

### 5.3 Seat Exhaustion

When all seats are booked, the route status transitions to **Full** and is excluded from future search results until a cancellation frees a seat.

---

## 6. Data Model (Route & Matching Relevant Entities)

### 6.1 Routes Table

```sql
CREATE TABLE routes (
    id              SERIAL PRIMARY KEY,
    driver_id       INTEGER NOT NULL REFERENCES users(id),
    vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
    origin          GEOGRAPHY(Point, 4326) NOT NULL,
    destination     GEOGRAPHY(Point, 4326) NOT NULL,
    route_geometry  GEOGRAPHY(LineString, 4326) NOT NULL,
    departure_time  TIMESTAMPTZ NOT NULL,
    flexibility_minutes INTEGER DEFAULT 15,
    duration_seconds INTEGER NOT NULL,       -- total route duration from routing API
    total_seats     INTEGER NOT NULL,
    available_seats INTEGER NOT NULL,
    recurrence      VARCHAR(20) DEFAULT 'one-time',  -- 'one-time', 'daily', 'weekdays', 'custom'
    recurrence_days INTEGER[],               -- for custom: array of ISO day numbers
    status          VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Spatial index for coarse matching
CREATE INDEX idx_routes_geometry ON routes USING GIST (route_geometry);

-- Compound index for status + seat filtering
CREATE INDEX idx_routes_active ON routes (status, available_seats)
    WHERE status = 'active' AND available_seats > 0;
```

### 6.2 Bookings Table

```sql
CREATE TABLE bookings (
    id              SERIAL PRIMARY KEY,
    route_id        INTEGER NOT NULL REFERENCES routes(id),
    passenger_id    INTEGER NOT NULL REFERENCES users(id),
    pickup_point    GEOGRAPHY(Point, 4326) NOT NULL,   -- closest point on route
    dropoff_point   GEOGRAPHY(Point, 4326) NOT NULL,   -- closest point on route
    pickup_walking_distance  INTEGER,          -- meters, actual road distance
    dropoff_walking_distance INTEGER,          -- meters, actual road distance
    estimated_pickup_time    TIMESTAMPTZ,
    status          VARCHAR(20) DEFAULT 'pending',     -- pending, confirmed, declined, cancelled, completed
    declined_reason TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 7. Technical Dependencies

| Component | Technology | Purpose |
|---|---|---|
| Spatial database | PostgreSQL + PostGIS | Route storage, coarse filtering, geometric operations |
| Routing API | Google Directions API or OSRM | Route path generation, walking distance calculation |
| Geocoding | Google Geocoding API | Reverse-geocoding pickup/dropoff points to readable names |
| Spatial indexing | GiST index | Performant spatial queries at scale |
| Caching | Redis (geohash-keyed) | Cache walking distance API results to reduce cost |

---

## 8. Known Limitations & Future Enhancements

| Limitation | Impact | Future Enhancement |
|---|---|---|
| Linear time interpolation along route | Pickup time estimates may be inaccurate in variable traffic | Segment-level duration estimates using traffic-aware routing |
| No driver detour tolerance | Passenger must walk to the route; no flexibility for drivers to deviate slightly | Configurable detour tolerance per driver, re-routing through pickup point |
| Single ranking signal (walking distance) | Doesn't account for price, rating, or time preference | Weighted composite scoring with tunable parameters |
| Walking distance API cost | Each candidate requires an external API call | Expanded caching, pre-computation for high-demand corridors |
| Static route path | Driver's actual daily route may vary slightly | GPS trace learning over multiple trips to build probabilistic route corridors |
| No recurring match optimization | Repeat passengers re-search daily | Proactive matching: detect repeat searches, notify when matching routes are posted |
