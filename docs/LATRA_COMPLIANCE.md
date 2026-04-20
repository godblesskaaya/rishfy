# LATRA Compliance Reference

> **Audience:** Every developer on the Rishfy team + the supervisor.
> **Purpose:** A single source of truth for which LATRA requirement each feature, database field, and API endpoint satisfies.
> **Owner:** Fatma Abdallah (Notification & LATRA integration lead)
> **Source document:** `Rishfy_LATRA_Requirements_Section.docx`

---

## 1. Why This Matters

LATRA's D5 ride-sharing category (introduced December 2024) is the regulatory framework Rishfy operates under. **Zero D5 licenses have been issued to date** — Rishfy is positioning as Tanzania's first licensed ride-sharing platform. This gives us a first-mover advantage but makes compliance non-negotiable.

LATRA organizes operator requirements into three stages:

1. **Stage 1 — Operational features** (in-app functionality)
2. **Stage 2 — Technical API integration** (reporting to LATRA systems)
3. **Stage 3 — Business licensing** (corporate registration, documentation)

Stages 1 and 2 are **in-scope for the academic project**. Stage 3 is post-commercialization.

---

## 2. Stage 1: Operational Requirements Mapping

Each LATRA operational requirement (LATRA-OR-XX) maps to one or more Rishfy functional requirements. When implementing a feature, check this table to understand the compliance obligation.

| LATRA Req. | Description | Rishfy Impl. | Service | Status |
|---|---|---|---|---|
| **LATRA-OR-01** | Customer registration + OTP verification | FR-UM-01, FR-UM-02 | auth-service | ✅ Fully compliant |
| **LATRA-OR-02** | Vehicle registration details (reg. no., make, model, color, LATRA status) | FR-VR-01 + `VEHICLE` entity | user-service | ✅ Fully compliant |
| **LATRA-OR-03** | Driver name + photo visible before booking | FR-RM-03 + `USER.profile_picture_url` | user-service, route-service | ✅ Fully compliant |
| **LATRA-OR-04** | Accurate GPS pickup & destination | FR-VR-03 + Google Maps API | route-service | ✅ Fully compliant |
| **LATRA-OR-05** | Real-time arrival estimate | ETA endpoint + scheduled departure display | location-service | ⚠️ Adapted (we're scheduled, not on-demand) |
| **LATRA-OR-06** | Vehicle movement tracking | FR-TR-01 to FR-TR-03, 30s sampling | location-service | ✅ Fully compliant |
| **LATRA-OR-07** | No charge on pre-arrival cancellation | FR-BK-06, 2-hour free window | booking-service, payment-service | ✅ Fully compliant |
| **LATRA-OR-08** | Emergency contact feature | Safety button + `EMERGENCY_CONTACT` entity | notification-service | 🟡 Planned Sprint 4 |
| **LATRA-OR-09** | Location-based fare calculation | Pre-agreed fare + post-trip verification | booking-service | ✅ Fully compliant |
| **LATRA-OR-10** | Digital receipt generation | `PAYMENT` + `TRIP` join | payment-service | ✅ Fully compliant |
| **LATRA-OR-11** | Trip status notifications | FR-NT-01, FR-NT-02 | notification-service | ✅ Fully compliant |

---

## 3. Stage 2: Technical API Integration

LATRA requires platform operators to expose an authenticated API that returns completed trip data in a standardized format.

### 3.1 Endpoint Specification

```
GET /api/v1/latra/trips
Authorization: Bearer <oauth2-token>
?start_date=2026-02-01T00:00:00Z
&end_date=2026-02-28T23:59:59Z
```

**Implementation:** `booking-service` → `GetTripsForLATRAReport` gRPC method (internal), exposed via the reporting REST endpoint.

### 3.2 Data Field Mapping

This is the authoritative mapping from LATRA's required fields to our database schema.

| # | LATRA Field | Rishfy Source | Format Notes |
|---|---|---|---|
| 1 | Trip ID | `booking.booking_id` or `trip.trip_id` | UUID stringified |
| 2 | Origin Coordinates | `route.origin_lat, route.origin_lng` | **Comma-separated**, e.g. `"-6.7924,39.2083"` |
| 3 | End Coordinates | `route.destination_lat, route.destination_lng` | Same format as origin |
| 4 | Start Time | `booking.trip_started_at` | **No 'T' separator**, format: `"YYYY-MM-DD HH:MM:SS"` |
| 5 | End Time | `booking.trip_completed_at` | Same format as start |
| 6 | Total Fare Amount | `payment.amount` | Integer, TZS minor units = 0 |
| 7 | Trip Distance | `trip.distance_meters` | **Meters**, not kilometers |
| 8 | Rating | `booking.passenger_rating` | 1-5; use 0 if no rating given |
| 9 | Driver's Earning | `payment.amount - platform_fee` | Calculated field |
| 10 | Driver License Number | `user.license_number` | Lookup via user-service gRPC |
| 11 | Vehicle Registration | `vehicle.registration_number` | Lookup via user-service gRPC |

### 3.3 Example Response

```json
{
  "trips": [
    {
      "trip_id": "7d3a1b2c-4e5f-6a7b-8c9d-0e1f2a3b4c5d",
      "origin_coordinates": "-6.7924,39.2083",
      "end_coordinates": "-6.8162,39.2803",
      "start_time": "2026-02-18 08:15:00",
      "end_time": "2026-02-18 08:47:00",
      "total_fare_amount": 5000,
      "trip_distance": 12500,
      "rating": 5,
      "driver_earning": 4250,
      "driver_license_number": "TZ-DL-2023-045678",
      "vehicle_registration": "T123ABC"
    }
  ],
  "next_cursor": "eyJsYXN0X2lkIjoiN2QzYTFiMmMifQ=="
}
```

### 3.4 Authentication

- **OAuth 2.0** client credentials flow (production)
- In dev/academic, we mock LATRA as a static client with a hardcoded token
- The `auth-service` issues service tokens scoped `latra:read` — only the reporting endpoint accepts them

### 3.5 Rate Limiting

Target: 100 requests/hour per LATRA client. Implemented at NGINX gateway with a dedicated `limit_req_zone` (see `nginx.conf`).

### 3.6 Vehicle Verification API (LATRA → Rishfy)

When a driver registers a new vehicle, Rishfy calls LATRA's verification endpoint to confirm the vehicle's license. In Phase 1 (academic), this is **mocked** — `latra_verified` is set to `true` for testing.

Mock implementation lives in `services/user/src/clients/latra-mock.ts`.

---

## 4. Stage 3: Business Licensing (Post-Academic)

Not implemented in the academic phase. For reference, LATRA requires:

1. Certificate of Incorporation
2. Business Plan
3. Strategic Plan (3-5 year)
4. Emergency Response Plan
5. Audited Financial Statements
6. MoU with fleet partners (if applicable)
7. TIN Certificate
8. Tax Clearance / VAT Certificate
9. Proof of Regulatory Levy Payment

**Team responsibility:** The supervisor and project team will prepare a separate commercialization roadmap document outside the codebase.

---

## 5. Code-Level Compliance Checklist

When implementing any feature, ask:

- [ ] Does this touch PII? If yes, is it encrypted at rest? Logged safely?
- [ ] Does this involve trip data? Are all 11 LATRA fields captured?
- [ ] Does this affect fare calculation? Is the formula transparent and pre-disclosed?
- [ ] Does this involve cancellation? Is the 2-hour free window honored?
- [ ] Does this involve notifications? Are trip-status events emitted for every state change?
- [ ] Does this touch the driver profile? Are license number + expiry validated on every route post?

---

## 6. Testing LATRA Compliance

**Compliance test suite:** `services/booking/tests/integration/latra-compliance.spec.ts`

This runs against a mock LATRA client and verifies:

1. All 11 fields are present in every response
2. Timestamp formatting matches spec (no 'T', no decimal seconds)
3. Coordinates use comma separators (not JSON arrays)
4. Distance is in meters
5. Pagination cursor is stable across requests
6. Unauthorized requests return 401
7. Tokens without `latra:read` scope return 403

Run with:

```bash
./scripts/dev.sh test booking -- --grep "LATRA"
```

---

## 7. Regulatory Roadmap

| Phase | Timeline | Deliverable |
|---|---|---|
| **Phase 1 (Academic)** | Now – Week 12 | All Stage 1 features operational + Stage 2 API with mock LATRA endpoints |
| **Phase 2 (Pre-commercialization)** | Post-graduation | Company registration, Stage 3 documentation prepared |
| **Phase 3 (Post-license)** | After LATRA approval | Live Stage 2 integration with production LATRA credentials |

---

## 8. Escalation & Questions

- **Technical questions about implementation** → Fatma (LATRA lead)
- **Regulatory interpretation** → Supervisor (Dr. Abdullah Ally)
- **Business licensing** → Out of scope for the dev team; handled by commercialization track

---

*Last updated: Sprint 0 kickoff. Review at the start of every sprint and update the "Status" column as features ship.*
