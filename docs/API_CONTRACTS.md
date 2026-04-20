# Rishfy API Contracts

> **Complete REST API specifications for all 7 services**
> Version: 1.0
> Base URL (dev): `http://localhost:8080/api/v1`
> Base URL (prod): `https://api.rishfy.co.tz/v1`

---

## Table of Contents

1. [API Conventions](#1-api-conventions)
2. [Authentication](#2-authentication)
3. [Error Handling](#3-error-handling)
4. [Auth Service API](#4-auth-service-api)
5. [User Service API](#5-user-service-api)
6. [Route Service API](#6-route-service-api)
7. [Booking Service API](#7-booking-service-api)
8. [Payment Service API](#8-payment-service-api)
9. [Location Service API](#9-location-service-api)
10. [Notification Service API](#10-notification-service-api)
11. [Admin API](#11-admin-api)

---

## 1. API Conventions

### 1.1 Base Rules

| Rule | Convention |
|------|-----------|
| Protocol | HTTPS only (TLS 1.3) in prod; HTTP in dev |
| Versioning | URL path: `/api/v1/...` |
| Format | JSON request/response (`Content-Type: application/json`) |
| Naming | `snake_case` for fields, `kebab-case` for URLs |
| Dates | ISO 8601 with timezone (`2026-03-15T08:23:45.000Z`) |
| IDs | Integer (SERIAL) for internal; UUID for public-facing tokens |
| Pagination | Cursor-based for lists (`?cursor=xyz&limit=20`) |
| Sorting | Query param: `?sort=-created_at,name` (- for desc) |
| Filtering | Query params: `?status=confirmed&from_date=2026-01-01` |
| Localization | `Accept-Language: en` or `sw` header |

### 1.2 Standard Response Envelope

**Success Response**:
```json
{
  "success": true,
  "data": { /* resource or resources */ },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2026-03-15T08:23:45.000Z"
  }
}
```

**List Response (Paginated)**:
```json
{
  "success": true,
  "data": [ /* items */ ],
  "pagination": {
    "cursor_next": "eyJpZCI6MTIzfQ==",
    "cursor_prev": null,
    "has_more": true,
    "total_count": 127
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2026-03-15T08:23:45.000Z"
  }
}
```

**Error Response**:
```json
{
  "success": false,
  "error": {
    "code": "BOOKING_SEATS_UNAVAILABLE",
    "message": "Only 1 seat available, you requested 2",
    "details": {
      "available_seats": 1,
      "requested_seats": 2
    },
    "trace_id": "abc123"
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2026-03-15T08:23:45.000Z"
  }
}
```

### 1.3 Standard Headers

**Request Headers**:
```
Authorization: Bearer <access_token>
Content-Type: application/json
Accept: application/json
Accept-Language: en | sw
X-Request-ID: <uuid>          (optional, generated if missing)
X-Device-ID: <device_id>       (for mobile apps)
X-App-Version: 1.2.3
```

**Response Headers**:
```
X-Request-ID: <uuid>
X-Rate-Limit-Remaining: 99
X-Rate-Limit-Reset: 1738367400
X-Response-Time: 87ms
```

### 1.4 Rate Limiting

| Endpoint Group | Limit | Scope |
|---------------|-------|-------|
| `/auth/login`, `/auth/register` | 5/min | Per IP |
| `/auth/send-otp` | 3/min | Per phone |
| Search endpoints | 60/min | Per user |
| Write endpoints | 30/min | Per user |
| Read endpoints | 300/min | Per user |
| Admin endpoints | 1000/min | Per admin |

---

## 2. Authentication

### 2.1 Token Flow

All protected endpoints require `Authorization: Bearer <access_token>`.

- **Access Token**: JWT, 15-minute TTL
- **Refresh Token**: Opaque string, 7-day TTL, stored server-side
- **Revocation**: Refresh tokens revoked on logout, password change, or admin action

### 2.2 JWT Payload

```json
{
  "sub": "123",
  "type": "driver",
  "verified": true,
  "iat": 1738367400,
  "exp": 1738368300,
  "jti": "unique-jwt-id"
}
```

### 2.3 Role Matrix

| Role | Can Access |
|------|-----------|
| `anonymous` | Public endpoints only (`/auth/*`, `/routes/search`) |
| `rider` | Own profile, bookings, payments |
| `driver` | Own profile, routes, vehicles, earnings |
| `admin` | All endpoints (audited) |

---

## 3. Error Handling

### 3.1 HTTP Status Codes

| Code | Use |
|------|-----|
| `200 OK` | Successful GET/PUT/PATCH |
| `201 Created` | Successful POST (resource created) |
| `204 No Content` | Successful DELETE |
| `400 Bad Request` | Validation error, malformed input |
| `401 Unauthorized` | Missing/invalid/expired token |
| `403 Forbidden` | Authenticated but not authorized |
| `404 Not Found` | Resource does not exist |
| `409 Conflict` | Duplicate resource, state conflict |
| `422 Unprocessable Entity` | Business rule violation |
| `429 Too Many Requests` | Rate limit hit |
| `500 Internal Server Error` | Unhandled exception |
| `503 Service Unavailable` | Downstream service unavailable |

### 3.2 Canonical Error Codes

| Code | HTTP | Description |
|------|------|-------------|
| `VALIDATION_ERROR` | 400 | Input validation failed |
| `AUTH_INVALID_CREDENTIALS` | 401 | Wrong phone/password |
| `AUTH_TOKEN_EXPIRED` | 401 | Access token expired |
| `AUTH_TOKEN_INVALID` | 401 | Malformed or invalid token |
| `AUTH_USER_LOCKED` | 401 | Account temporarily locked |
| `AUTH_OTP_INVALID` | 400 | Wrong OTP code |
| `AUTH_OTP_EXPIRED` | 400 | OTP expired |
| `AUTH_OTP_MAX_ATTEMPTS` | 429 | Too many OTP attempts |
| `PERMISSION_DENIED` | 403 | Role lacks permission |
| `RESOURCE_NOT_FOUND` | 404 | Entity doesn't exist |
| `RESOURCE_CONFLICT` | 409 | Duplicate resource |
| `BOOKING_SEATS_UNAVAILABLE` | 422 | Not enough seats |
| `BOOKING_ROUTE_DEPARTED` | 422 | Route already departed |
| `BOOKING_ALREADY_CANCELLED` | 422 | Can't cancel cancelled booking |
| `PAYMENT_FAILED` | 422 | Mobile money rejected |
| `PAYMENT_ALREADY_PAID` | 409 | Booking already paid |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `SERVICE_UNAVAILABLE` | 503 | Downstream failure |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## 4. Auth Service API

**Base Path**: `/api/v1/auth`
**Service**: `auth-service` on port 3001
**Owner**: Stella

### 4.1 Register User

Register a new rider or driver. Sends OTP to phone.

```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "phone": "+255712345678",
  "email": "john@example.com",
  "password": "SecurePass123!",
  "first_name": "John",
  "last_name": "Doe",
  "user_type": "rider"
}
```

**Validation**:
- `phone`: E.164 format, Tanzania prefix (`+255...`)
- `email`: Valid email (optional, required for admin)
- `password`: Min 8 chars, 1 uppercase, 1 digit, 1 special
- `user_type`: `rider` or `driver`

**Response `201 Created`**:
```json
{
  "success": true,
  "data": {
    "user_id": 123,
    "phone": "+255712345678",
    "verification_required": true,
    "otp_sent_to": "+255712345678",
    "otp_expires_at": "2026-03-15T08:28:45.000Z"
  }
}
```

**Errors**: `RESOURCE_CONFLICT` (409, phone already registered), `VALIDATION_ERROR` (400)

---

### 4.2 Verify OTP

Complete registration by verifying OTP.

```http
POST /api/v1/auth/verify-otp
Content-Type: application/json

{
  "phone": "+255712345678",
  "code": "123456",
  "type": "registration"
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGc...",
    "refresh_token": "rt_abc123...",
    "access_token_expires_in": 900,
    "refresh_token_expires_in": 604800,
    "user": {
      "id": 123,
      "phone": "+255712345678",
      "user_type": "rider",
      "verified": true
    }
  }
}
```

**Errors**: `AUTH_OTP_INVALID`, `AUTH_OTP_EXPIRED`, `AUTH_OTP_MAX_ATTEMPTS`

---

### 4.3 Login

Authenticate with phone + password.

```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "phone": "+255712345678",
  "password": "SecurePass123!",
  "device_id": "device_abc123",
  "device_info": {
    "platform": "android",
    "model": "Samsung Galaxy A52",
    "os_version": "13"
  }
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGc...",
    "refresh_token": "rt_abc123...",
    "access_token_expires_in": 900,
    "refresh_token_expires_in": 604800,
    "user": {
      "id": 123,
      "phone": "+255712345678",
      "user_type": "rider",
      "verified": true
    }
  }
}
```

**Errors**: `AUTH_INVALID_CREDENTIALS` (401), `AUTH_USER_LOCKED` (401)

---

### 4.4 Refresh Token

Exchange refresh token for new access token.

```http
POST /api/v1/auth/refresh-token
Content-Type: application/json

{
  "refresh_token": "rt_abc123..."
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGc...",
    "refresh_token": "rt_new456...",
    "access_token_expires_in": 900,
    "refresh_token_expires_in": 604800
  }
}
```

**Note**: Returns a NEW refresh token (rotation). Old one is revoked.

---

### 4.5 Send OTP

Request a new OTP code (e.g., for password reset).

```http
POST /api/v1/auth/send-otp
Content-Type: application/json

{
  "phone": "+255712345678",
  "type": "password_reset"
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "otp_sent": true,
    "expires_at": "2026-03-15T08:28:45.000Z",
    "resend_available_at": "2026-03-15T08:24:45.000Z"
  }
}
```

---

### 4.6 Reset Password

```http
POST /api/v1/auth/reset-password
Content-Type: application/json

{
  "phone": "+255712345678",
  "otp_code": "123456",
  "new_password": "NewSecurePass456!"
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "message": "Password reset successful. Please login with your new password."
  }
}
```

**Side effect**: All existing refresh tokens are revoked.

---

### 4.7 Change Password (Authenticated)

```http
POST /api/v1/auth/change-password
Authorization: Bearer <token>
Content-Type: application/json

{
  "current_password": "OldPass123!",
  "new_password": "NewPass456!"
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": { "message": "Password changed successfully" }
}
```

---

### 4.8 Logout

Revoke refresh token.

```http
POST /api/v1/auth/logout
Authorization: Bearer <token>
Content-Type: application/json

{
  "refresh_token": "rt_abc123..."
}
```

**Response `204 No Content`**

---

### 4.9 Validate Token (Internal/Gateway)

Used by API Gateway to validate tokens. Not exposed externally.

```http
POST /api/v1/auth/validate
Content-Type: application/json

{
  "token": "eyJhbGc..."
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "valid": true,
    "user_id": 123,
    "user_type": "rider",
    "verified": true
  }
}
```

---

## 5. User Service API

**Base Path**: `/api/v1/users`
**Service**: `user-service` on port 3002
**Owner**: Stella

### 5.1 Get Current User Profile

```http
GET /api/v1/users/me
Authorization: Bearer <token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "id": 123,
    "auth_id": 42,
    "first_name": "John",
    "last_name": "Doe",
    "phone": "+255712345678",
    "email": "john@example.com",
    "profile_picture_url": "https://cdn.rishfy.co.tz/users/123.jpg",
    "date_of_birth": "1990-05-15",
    "gender": "male",
    "preferred_language": "en",
    "preferred_payment_method": "m-pesa",
    "notification_preferences": {
      "push": true,
      "sms": true,
      "email": false
    },
    "emergency_contact": {
      "name": "Jane Doe",
      "phone": "+255712345679"
    },
    "driver_profile": null,
    "created_at": "2026-01-15T08:00:00.000Z"
  }
}
```

---

### 5.2 Update Profile

```http
PATCH /api/v1/users/me
Authorization: Bearer <token>
Content-Type: application/json

{
  "first_name": "Johnathan",
  "preferred_language": "sw",
  "emergency_contact_name": "Jane Doe",
  "emergency_contact_phone": "+255712345679"
}
```

**Response `200 OK`**: Same shape as `GET /users/me`

---

### 5.3 Upload Profile Picture

```http
POST /api/v1/users/me/profile-picture
Authorization: Bearer <token>
Content-Type: multipart/form-data

file: <binary>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "profile_picture_url": "https://cdn.rishfy.co.tz/users/123.jpg"
  }
}
```

---

### 5.4 Register as Driver

Upgrades a rider to driver (keeps rider capability).

```http
POST /api/v1/users/me/become-driver
Authorization: Bearer <token>
Content-Type: application/json

{
  "license_number": "TZ-DL-2023-045678",
  "license_expiry": "2028-05-15",
  "license_photo_url": "https://cdn.rishfy.co.tz/licenses/abc.jpg"
}
```

**Response `201 Created`**:
```json
{
  "success": true,
  "data": {
    "driver_profile": {
      "id": 45,
      "user_id": 123,
      "license_number": "TZ-DL-2023-045678",
      "license_verified": false,
      "latra_verified": false,
      "status": "offline",
      "rating_avg": 5.00
    }
  }
}
```

---

### 5.5 Get Driver Public Profile

Public info about a driver (for passengers browsing routes).

```http
GET /api/v1/users/drivers/{driver_id}/public
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "driver_id": 45,
    "first_name": "John",
    "profile_picture_url": "https://cdn.rishfy.co.tz/users/123.jpg",
    "rating_avg": 4.85,
    "rating_count": 127,
    "completed_trips": 245,
    "latra_verified": true,
    "member_since": "2026-01-15",
    "active_vehicle": {
      "make": "Toyota",
      "model": "Corolla",
      "color": "Silver",
      "registration_number": "T123ABC",
      "capacity": 4
    }
  }
}
```

---

### 5.6 Add Vehicle (Driver Only)

```http
POST /api/v1/users/me/vehicles
Authorization: Bearer <token>
Content-Type: application/json

{
  "registration_number": "T123ABC",
  "make": "Toyota",
  "model": "Corolla",
  "year": 2020,
  "color": "Silver",
  "capacity": 4,
  "vehicle_type": "sedan",
  "insurance_company": "Heritage Insurance",
  "insurance_policy_number": "POL-2026-12345",
  "insurance_expiry": "2027-03-15",
  "photos": [
    {"url": "https://...", "type": "front"},
    {"url": "https://...", "type": "back"}
  ]
}
```

**Response `201 Created`**:
```json
{
  "success": true,
  "data": {
    "vehicle": {
      "id": 78,
      "registration_number": "T123ABC",
      "make": "Toyota",
      "model": "Corolla",
      "capacity": 4,
      "latra_verified": false,
      "active": true
    }
  }
}
```

---

### 5.7 List My Vehicles

```http
GET /api/v1/users/me/vehicles
Authorization: Bearer <token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": [
    {
      "id": 78,
      "registration_number": "T123ABC",
      "make": "Toyota",
      "model": "Corolla",
      "capacity": 4,
      "active": true,
      "is_active_vehicle": true
    }
  ]
}
```

---

### 5.8 Set Active Vehicle

```http
PUT /api/v1/users/me/active-vehicle
Authorization: Bearer <token>
Content-Type: application/json

{
  "vehicle_id": 78
}
```

**Response `200 OK`**

---

### 5.9 Register Device (for Push Notifications)

```http
POST /api/v1/users/me/devices
Authorization: Bearer <token>
Content-Type: application/json

{
  "device_id": "device_abc123",
  "platform": "android",
  "fcm_token": "fcm_token_xyz789...",
  "app_version": "1.2.3",
  "os_version": "13"
}
```

**Response `201 Created`**

---

## 6. Route Service API

**Base Path**: `/api/v1/routes`
**Service**: `route-service` on port 3003
**Owner**: Godbless

### 6.1 Search Routes

Search for routes matching origin/destination (primary passenger endpoint).

```http
GET /api/v1/routes/search?origin_lat=-6.7924&origin_lng=39.2083&destination_lat=-6.8162&destination_lng=39.2803&departure_from=2026-03-16T06:00:00Z&departure_to=2026-03-16T10:00:00Z&min_seats=1&radius_km=2
```

**Query Parameters**:
- `origin_lat`, `origin_lng` (required): Pickup location
- `destination_lat`, `destination_lng` (required): Drop-off location
- `departure_from`, `departure_to` (optional): Time window
- `min_seats` (optional, default 1): Minimum available seats
- `radius_km` (optional, default 2): Search radius around points
- `sort` (optional, default `departure_time`): `departure_time`, `-price_per_seat`, `-rating_avg`

**Response `200 OK`**:
```json
{
  "success": true,
  "data": [
    {
      "id": 1234,
      "driver": {
        "id": 45,
        "first_name": "John",
        "profile_picture_url": "https://...",
        "rating_avg": 4.85,
        "latra_verified": true
      },
      "vehicle": {
        "make": "Toyota",
        "model": "Corolla",
        "color": "Silver",
        "capacity": 4
      },
      "origin": {
        "name": "Mbezi Beach",
        "lat": -6.7924,
        "lng": 39.2083
      },
      "destination": {
        "name": "Kariakoo",
        "lat": -6.8162,
        "lng": 39.2803
      },
      "departure_time": "2026-03-16T08:00:00.000Z",
      "estimated_arrival": "2026-03-16T08:45:00.000Z",
      "available_seats": 3,
      "total_seats": 4,
      "price_per_seat": 3500,
      "currency": "TZS",
      "distance_km": 12.5,
      "duration_minutes": 45,
      "match_score": 0.92
    }
  ],
  "pagination": {
    "cursor_next": "eyJpZCI6MTIzNH0=",
    "has_more": false,
    "total_count": 7
  }
}
```

---

### 6.2 Get Route Details

```http
GET /api/v1/routes/{route_id}
```

**Response `200 OK`**: Full route object including route polyline for map display.

---

### 6.3 Create Route (Driver Only)

```http
POST /api/v1/routes
Authorization: Bearer <token>
Content-Type: application/json

{
  "origin": {
    "name": "Mbezi Beach",
    "lat": -6.7924,
    "lng": 39.2083,
    "place_id": "ChIJ..."
  },
  "destination": {
    "name": "Kariakoo",
    "lat": -6.8162,
    "lng": 39.2803,
    "place_id": "ChIJ..."
  },
  "departure_time": "2026-03-16T08:00:00.000Z",
  "total_seats": 4,
  "price_per_seat": 3500,
  "currency": "TZS",
  "route_type": "one-time",
  "notes": "AC, music on low",
  "preferences": {
    "music": true,
    "smoking": false,
    "pets": false,
    "luggage": true
  }
}
```

**Recurring Route** (replace `route_type`):
```json
{
  "route_type": "recurring",
  "recurrence_pattern": {
    "days": ["MON", "TUE", "WED", "THU", "FRI"],
    "start_date": "2026-03-16",
    "end_date": "2026-06-30",
    "time": "08:00"
  }
}
```

**Response `201 Created`**:
```json
{
  "success": true,
  "data": {
    "route": {
      "id": 1234,
      "driver_id": 45,
      "status": "scheduled",
      "available_seats": 4,
      "total_seats": 4,
      "distance_km": 12.5,
      "duration_minutes": 45,
      "route_polyline": "encodedPolyString...",
      "departure_time": "2026-03-16T08:00:00.000Z"
    }
  }
}
```

**Errors**: `PERMISSION_DENIED` (not a verified driver), `VALIDATION_ERROR` (invalid coordinates)

---

### 6.4 Update Route

```http
PATCH /api/v1/routes/{route_id}
Authorization: Bearer <token>
Content-Type: application/json

{
  "price_per_seat": 3000,
  "notes": "Updated: departing 15 min early"
}
```

**Constraints**:
- Cannot change origin/destination if bookings exist
- Cannot reduce `total_seats` below `total_seats - available_seats` (i.e., can't evict booked seats)

---

### 6.5 Cancel Route

```http
DELETE /api/v1/routes/{route_id}
Authorization: Bearer <token>
Content-Type: application/json

{
  "reason": "Vehicle breakdown"
}
```

**Response `200 OK`**

**Side effects**:
- All pending/confirmed bookings on this route are auto-cancelled
- Refunds initiated for paid bookings
- Notifications sent to affected passengers

---

### 6.6 List My Routes (Driver)

```http
GET /api/v1/routes/me?status=scheduled&from_date=2026-03-15
Authorization: Bearer <token>
```

---

### 6.7 Reserve Seats (Internal — called by Booking Service)

```http
POST /api/v1/routes/{route_id}/reserve-seats
Authorization: Bearer <internal-service-token>
Content-Type: application/json

{
  "seats": 2,
  "reservation_id": "bk_123",
  "ttl_seconds": 120
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "reserved": true,
    "available_seats_after": 2,
    "reservation_expires_at": "2026-03-15T08:25:45.000Z"
  }
}
```

**Used by**: Booking Service (via gRPC primarily, REST as fallback)

---

## 7. Booking Service API

**Base Path**: `/api/v1/bookings`
**Service**: `booking-service` on port 3004
**Owner**: Ezekiel

### 7.1 Create Booking

```http
POST /api/v1/bookings
Authorization: Bearer <token>
Content-Type: application/json

{
  "route_id": 1234,
  "seats_booked": 2,
  "pickup": {
    "lat": -6.7924,
    "lng": 39.2083,
    "address": "Mbezi Beach, Near Mlimani City",
    "notes": "I'll be near the ATM"
  },
  "dropoff": {
    "lat": -6.8162,
    "lng": 39.2803,
    "address": "Kariakoo Market",
    "notes": null
  }
}
```

**Response `201 Created`**:
```json
{
  "success": true,
  "data": {
    "booking": {
      "id": 5678,
      "confirmation_code": "A1B2C3D4",
      "route_id": 1234,
      "passenger_id": 123,
      "seats_booked": 2,
      "price_per_seat": 3500,
      "total_amount": 7000,
      "platform_fee": 1050,
      "driver_earning": 5950,
      "currency": "TZS",
      "status": "pending",
      "expires_at": "2026-03-15T08:25:45.000Z",
      "pickup": { /* ... */ },
      "dropoff": { /* ... */ },
      "created_at": "2026-03-15T08:23:45.000Z"
    },
    "next_step": {
      "action": "initiate_payment",
      "endpoint": "/api/v1/payments/initiate",
      "required_payload": {
        "booking_id": 5678,
        "payment_method": "m-pesa"
      }
    }
  }
}
```

**Errors**: `BOOKING_SEATS_UNAVAILABLE` (422), `BOOKING_ROUTE_DEPARTED` (422)

**Lifecycle**: Booking is `pending` for 2 minutes. If payment not completed, booking auto-cancels and seats released.

---

### 7.2 Get Booking Details

```http
GET /api/v1/bookings/{booking_id}
Authorization: Bearer <token>
```

**Response `200 OK`**: Full booking with route summary, driver info, trip status.

---

### 7.3 List My Bookings (Passenger)

```http
GET /api/v1/bookings/me?status=confirmed&limit=20&cursor=<cursor>
Authorization: Bearer <token>
```

**Query Parameters**:
- `status`: `pending`, `confirmed`, `active`, `completed`, `cancelled`
- `from_date`, `to_date`: ISO 8601
- `limit` (max 50, default 20)
- `cursor`: pagination cursor

---

### 7.4 Cancel Booking

```http
POST /api/v1/bookings/{booking_id}/cancel
Authorization: Bearer <token>
Content-Type: application/json

{
  "reason": "Plans changed"
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "booking_id": 5678,
    "status": "cancelled",
    "cancellation_charge": 0,
    "refund_amount": 7000,
    "refund_status": "initiated",
    "expected_refund_at": "2026-03-17T08:00:00.000Z"
  }
}
```

**Refund Rules**:
- Cancelled ≥ 2 hours before departure: Full refund
- Cancelled 30 min – 2 hours before: 50% refund
- Cancelled < 30 min before: No refund
- Cancelled by driver/platform: Full refund regardless

---

### 7.5 Start Trip (Driver Only)

Driver marks trip as started (pickup made).

```http
POST /api/v1/bookings/{booking_id}/start-trip
Authorization: Bearer <token>
Content-Type: application/json

{
  "start_lat": -6.7924,
  "start_lng": 39.2083
}
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "trip": {
      "id": 890,
      "booking_id": 5678,
      "status": "in_progress",
      "actual_start_time": "2026-03-16T08:02:00.000Z"
    }
  }
}
```

---

### 7.6 Complete Trip (Driver Only)

```http
POST /api/v1/bookings/{booking_id}/complete-trip
Authorization: Bearer <token>
Content-Type: application/json

{
  "end_lat": -6.8162,
  "end_lng": 39.2803
}
```

**Response `200 OK`**: Trip summary with actual distance/duration.

---

### 7.7 Submit Rating

```http
POST /api/v1/bookings/{booking_id}/rate
Authorization: Bearer <token>
Content-Type: application/json

{
  "rating_value": 5,
  "comment": "Great driver, very punctual!",
  "tags": ["punctual", "clean_car", "friendly"]
}
```

**Response `201 Created`**

---

### 7.8 Emergency Trigger

```http
POST /api/v1/bookings/{booking_id}/emergency
Authorization: Bearer <token>
Content-Type: application/json

{
  "notes": "Feeling unsafe",
  "lat": -6.8000,
  "lng": 39.2500
}
```

**Side effects**:
- Alerts admin dashboard
- SMS to user's emergency contact
- Flags trip as `disputed` for review

---

## 8. Payment Service API

**Base Path**: `/api/v1/payments`
**Service**: `payment-service` on port 3005
**Owner**: Ezekiel

### 8.1 Initiate Payment

Initiates mobile money STK push.

```http
POST /api/v1/payments/initiate
Authorization: Bearer <token>
Content-Type: application/json
Idempotency-Key: idm_abc123unique

{
  "booking_id": 5678,
  "payment_method": "m-pesa",
  "phone_number": "+255712345678"
}
```

**Response `202 Accepted`**:
```json
{
  "success": true,
  "data": {
    "payment_id": 9012,
    "transaction_reference": "RSH_2026031508234567_9012",
    "status": "processing",
    "provider_reference": "ws_CO_15032026082345123",
    "instructions": {
      "en": "Enter your M-Pesa PIN on your phone to complete payment.",
      "sw": "Ingiza PIN yako ya M-Pesa kwenye simu yako kukamilisha malipo."
    },
    "expires_at": "2026-03-15T08:25:45.000Z",
    "poll_url": "/api/v1/payments/9012/status"
  }
}
```

---

### 8.2 Get Payment Status

```http
GET /api/v1/payments/{payment_id}/status
Authorization: Bearer <token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "payment_id": 9012,
    "status": "completed",
    "amount": 7000,
    "currency": "TZS",
    "payment_method": "m-pesa",
    "external_reference": "SGK4FXJ89L",
    "paid_at": "2026-03-15T08:24:32.000Z",
    "booking_status": "confirmed"
  }
}
```

**Status values**: `pending`, `processing`, `completed`, `failed`, `cancelled`

---

### 8.3 Payment Webhook (Internal)

Received from M-Pesa/TigoPesa/Airtel. Not exposed to clients.

```http
POST /api/v1/payments/webhooks/{provider}
Content-Type: application/json
X-Signature: <HMAC>

{
  "transaction_id": "SGK4FXJ89L",
  "internal_reference": "RSH_2026031508234567_9012",
  "amount": 7000,
  "status": "completed",
  "payer_phone": "+255712345678",
  "timestamp": "2026-03-15T08:24:32.000Z"
}
```

**Response `200 OK`** (always, to acknowledge receipt; processed async)

**Signature verification**: Required per provider.

---

### 8.4 List My Payments

```http
GET /api/v1/payments/me?status=completed&limit=20
Authorization: Bearer <token>
```

---

### 8.5 Driver Earnings Summary

```http
GET /api/v1/payments/earnings/me?from_date=2026-03-01&to_date=2026-03-15
Authorization: Bearer <token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "period": {
      "from": "2026-03-01",
      "to": "2026-03-15"
    },
    "totals": {
      "gross_earnings": 125000,
      "platform_fees": 18750,
      "net_earnings": 106250,
      "currency": "TZS"
    },
    "trips_completed": 42,
    "average_per_trip": 2976,
    "pending_payout": 8500,
    "last_payout_date": "2026-03-14"
  }
}
```

---

### 8.6 Request Refund (Admin)

```http
POST /api/v1/payments/{payment_id}/refund
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "amount": 7000,
  "reason": "Driver no-show",
  "refund_type": "full"
}
```

---

## 9. Location Service API

**Base Path**: `/api/v1/location`
**Service**: `location-service` on port 3006
**Owner**: Godbless

**Note**: Most interactions use WebSocket for real-time. REST is for queries/reports.

### 9.1 WebSocket Connection

```
ws://localhost:3006/ws?token=<access_token>
```

**Namespaces**:
- `/driver` — Drivers send location updates
- `/passenger` — Passengers subscribe to driver location on active trips

#### Driver Emits: `location.update`
```json
{
  "trip_id": 890,
  "lat": -6.8000,
  "lng": 39.2500,
  "accuracy": 5.0,
  "bearing": 127,
  "speed": 12.5,
  "altitude": 45,
  "timestamp": "2026-03-15T08:15:30.000Z"
}
```

#### Passenger Subscribes: `trip.subscribe`
```json
{
  "trip_id": 890
}
```

#### Server Emits: `driver.location.updated`
```json
{
  "trip_id": 890,
  "lat": -6.8000,
  "lng": 39.2500,
  "bearing": 127,
  "speed": 12.5,
  "estimated_arrival": "2026-03-15T08:25:00.000Z",
  "timestamp": "2026-03-15T08:15:30.000Z"
}
```

#### Server Emits: `driver.arrived`
```json
{
  "trip_id": 890,
  "arrival_time": "2026-03-15T08:23:00.000Z"
}
```

---

### 9.2 Get Current Driver Location (REST)

```http
GET /api/v1/location/drivers/{driver_id}/current
Authorization: Bearer <token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "driver_id": 45,
    "lat": -6.8000,
    "lng": 39.2500,
    "bearing": 127,
    "speed": 12.5,
    "last_update": "2026-03-15T08:15:30.000Z",
    "status": "online"
  }
}
```

**Authorization**: Only passenger on active trip with this driver can query.

---

### 9.3 Get Trip Track (Completed Trips)

```http
GET /api/v1/location/trips/{trip_id}/track
Authorization: Bearer <token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": {
    "trip_id": 890,
    "path": [
      {"lat": -6.7924, "lng": 39.2083, "timestamp": "..."},
      {"lat": -6.7950, "lng": 39.2100, "timestamp": "..."}
    ],
    "distance_km": 12.5,
    "duration_sec": 2700,
    "start_time": "2026-03-15T08:00:00.000Z",
    "end_time": "2026-03-15T08:45:00.000Z"
  }
}
```

---

### 9.4 Find Nearby Drivers (Internal)

Used by Route Service to suggest drivers for ad-hoc requests.

```http
GET /api/v1/location/drivers/nearby?lat=-6.7924&lng=39.2083&radius_km=5
Authorization: Bearer <internal-token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": [
    {
      "driver_id": 45,
      "distance_km": 1.2,
      "lat": -6.8000,
      "lng": 39.2100,
      "last_update": "2026-03-15T08:15:30.000Z"
    }
  ]
}
```

---

## 10. Notification Service API

**Base Path**: `/api/v1/notifications`
**Service**: `notification-service` on port 3007
**Owner**: Fatma

### 10.1 List My Notifications

```http
GET /api/v1/notifications/me?read=false&limit=20
Authorization: Bearer <token>
```

**Response `200 OK`**:
```json
{
  "success": true,
  "data": [
    {
      "id": 456,
      "type": "booking_confirmed",
      "title": "Booking Confirmed",
      "message": "Your booking with John is confirmed for tomorrow 8 AM",
      "data": {
        "booking_id": 5678,
        "action": "view_booking"
      },
      "read": false,
      "priority": "normal",
      "created_at": "2026-03-15T08:24:45.000Z"
    }
  ],
  "pagination": { /* ... */ }
}
```

---

### 10.2 Mark Notification as Read

```http
PATCH /api/v1/notifications/{id}/read
Authorization: Bearer <token>
```

---

### 10.3 Mark All as Read

```http
POST /api/v1/notifications/me/mark-all-read
Authorization: Bearer <token>
```

---

### 10.4 Update Notification Preferences

```http
PATCH /api/v1/notifications/me/preferences
Authorization: Bearer <token>
Content-Type: application/json

{
  "push": true,
  "sms": true,
  "email": false,
  "categories": {
    "booking_updates": true,
    "payment_updates": true,
    "marketing": false
  }
}
```

---

### 10.5 Send Notification (Internal)

Used by other services to trigger notifications.

```http
POST /api/v1/notifications/send
Authorization: Bearer <internal-token>
Content-Type: application/json

{
  "user_id": 123,
  "type": "booking_confirmed",
  "template_name": "booking_confirmed",
  "variables": {
    "driver_name": "John",
    "departure_time": "8:00 AM"
  },
  "channels": ["push", "sms"],
  "priority": "high"
}
```

---

## 11. Admin API

**Base Path**: `/api/v1/admin`
**Access**: `admin` role only
**Auditing**: Every request logged to immutable audit table

### 11.1 List Users

```http
GET /api/v1/admin/users?user_type=driver&status=active&search=john&limit=50
Authorization: Bearer <admin-token>
```

### 11.2 Suspend User

```http
POST /api/v1/admin/users/{user_id}/suspend
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "reason": "Multiple fraud reports",
  "duration_days": 30
}
```

### 11.3 Verify Driver LATRA

```http
POST /api/v1/admin/drivers/{driver_id}/verify-latra
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "latra_license_number": "D5-2026-00123",
  "latra_license_expiry": "2027-12-31"
}
```

### 11.4 Get Platform Metrics

```http
GET /api/v1/admin/metrics?from_date=2026-03-01&to_date=2026-03-15
Authorization: Bearer <admin-token>
```

**Response**:
```json
{
  "success": true,
  "data": {
    "users": {
      "total": 1245,
      "new_in_period": 87,
      "active_in_period": 456
    },
    "drivers": {
      "total": 145,
      "latra_verified": 89,
      "active_in_period": 67
    },
    "bookings": {
      "created": 892,
      "completed": 756,
      "cancelled": 98,
      "cancellation_rate": 0.11
    },
    "revenue": {
      "total_processed": 6234000,
      "platform_fees": 935100,
      "currency": "TZS"
    }
  }
}
```

### 11.5 Export LATRA Report

```http
GET /api/v1/admin/latra/report?from_date=2026-03-14&to_date=2026-03-14&format=json
Authorization: Bearer <admin-token>
```

**Response** matches the LATRA-specified JSON format (11 required fields per trip).

---

## OpenAPI Specification Files

Full machine-readable OpenAPI 3.0 specs are stored per service in:

```
api-contracts/
├── auth-service.yaml
├── user-service.yaml
├── route-service.yaml
├── booking-service.yaml
├── payment-service.yaml
├── location-service.yaml
├── notification-service.yaml
└── admin-api.yaml
```

These power Swagger UI at `http://localhost:8080/docs` and are used by:
- Mobile app code generation (via `openapi-generator`)
- Postman collections (auto-imported)
- Contract testing (Pact)

---

**Document Owner**: Backend Team
**Last Updated**: 2026-03-15
**Version**: 1.0
**Status**: Approved for Development
