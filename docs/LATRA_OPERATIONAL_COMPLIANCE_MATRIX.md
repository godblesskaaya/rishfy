# LATRA Operational Compliance Matrix

Purpose: track LATRA ride-hailing operational requirements against Rishfy's scheduled shared-route mission. The target is not to copy on-demand taxi apps; the target is to pass LATRA review with explicit adaptations where the regulation assumes pure ride hailing.

Source baseline: LATRA "Operate a Ride Hailing System" guide and Ride Hailing Service Operator License Guide.

Status legend:
- Met: implemented in product flow.
- Adapted: implemented in a Rishfy-specific way that should be explained during review.
- Partial: implemented but missing production hardening, verification, or a complete UX.
- Missing: not implemented.
- Not applicable: intentionally excluded because it conflicts with scheduled shared mobility and is not explicitly required.

| LATRA item | Rishfy interpretation | Current status | Evidence | Completion criteria |
| --- | --- | --- | --- | --- |
| Customer registration and OTP verification | Account registration remains mandatory for booking and driving. | Met | `services/auth/src/services/auth.service.ts`, `mobile/lib/features/auth/presentation/screens/otp_verification_screen.dart` | OTP can be demonstrated end to end in staging. |
| Vehicle registration details | Drivers register vehicles used to post shared routes. | Met | `services/user/src/repositories/user.repository.ts`, `mobile/lib/features/profile/presentation/screens/vehicle_management_screen.dart` | Admin can see each vehicle's make, model, color, plate, capacity, approval status. |
| Driver details such as name and photo | Driver identity appears before and after booking. | Partial | `mobile/lib/features/profile/presentation/screens/public_driver_profile_screen.dart`, `mobile/lib/features/profile/presentation/screens/edit_profile_screen.dart` | Replace URL-only photo entry with in-app upload through the existing presigned upload endpoint. |
| Ability to request a ride and set accurate start/destination | Passenger books a seat on a scheduled route with pickup and dropoff points. | Adapted | `services/route/src/services/route.service.ts`, `services/booking/src/services/booking.service.ts` | Review script explains "request ride" as "book route seat"; route search must show pickup/dropoff coordinates. |
| Real-time estimate for driver reaching pickup | ETA is shown once a route/trip is active, not during idle on-demand dispatch. | Adapted | `services/location/src/services/live-trip.service.ts`, `mobile/lib/features/trip/data/models/location_models.dart` | Active trip screen displays current ETA or marks ETA stale. |
| Vehicle movement to pickup and destination | Driver location is broadcast and passenger sees active trip movement. | Met | `mobile/lib/features/trip/presentation/providers/trip_provider.dart`, `services/location/src/repositories/location.repository.ts` | LATRA test account can observe vehicle movement during an active route run. |
| Trip cancellation without charge before trip has started or driver has arrived | Cancellation is allowed before boarding; paid bookings trigger refund, and provider automation failure creates a manual-required refund record. | Met / adapted | `services/booking/src/services/booking.service.ts`, `services/booking/tests/unit/booking.service.spec.ts`, `services/payment/src/services/payment.service.ts`, `services/payment/tests/unit/payment.service.spec.ts` | Staging payment provider must prove refund execution; operations dashboard should monitor manual-required refund rows. |
| Contact or emergency contact | Users can manage emergency contacts and submit in-trip safety reports. | Met | `mobile/lib/features/profile/presentation/providers/emergency_contacts_provider.dart`, `services/booking/src/controllers/booking.routes.ts` | Emergency contact data loads from backend and safety report appears in history. |
| Ending trip charges based on ended location | Rishfy uses pre-agreed shared-route fare and reports tracked route-run distance when available. | Adapted | `services/booking/src/services/latra.service.ts`, `services/booking/src/clients/location.grpc.client.ts`, `services/booking/tests/unit/latra.service.spec.ts` | Demonstrate to LATRA why shared-route fare is agreed upfront; staging records should include tracked trip points for completed trips. |
| Receipt after trip with start point, end point, fare and time | Receipt screens exist and payment detail is available. | Partial | `mobile/lib/features/bookings/presentation/screens/booking_receipt_screen.dart` | Receipt always shows start, end, fare, start time, end time, payment/refund status. |
| Notify customer when driver arrives, trip starts and trip ends | Booking/trip events are routed to notifications, and safety/system-critical events bypass user opt-out. | Partial | `services/notification/src/consumers/notification.consumers.ts`, `services/notification/src/services/notification.service.ts`, `services/notification/tests/unit/notification.dispatch.spec.ts` | SMS adapter must be real or explicitly excluded for review; staging should prove arrival/start/end templates reach passenger channels. |
| Stage 2 completed rides API | Rishfy exposes completed trips by date in LATRA's 11-field shape with validation metadata. | Partial | `services/booking/src/controllers/booking.routes.ts`, `services/booking/src/services/latra.service.ts`, `services/booking/tests/unit/latra.service.spec.ts` | Endpoint returns complete records with zero missing fields in staging data and real LATRA OAuth credentials. |
| Stage 2 OAuth 2.0 authentication | Mock OAuth endpoint exists for LATRA integration rehearsal and is disabled in production. | Partial | `services/booking/src/controllers/booking.routes.ts` | Replace mock with LATRA credentials once issued; enforce scope-based access. |
| LATRA vehicle verification API | Mock vehicle verification exists for onboarding rehearsal and is disabled in production. | Partial | `services/booking/src/services/latra.service.ts`, `services/booking/src/controllers/booking.routes.ts` | User/admin vehicle approval calls real LATRA API when access is granted. |

Mission guardrails:
- Keep scheduled shared-route booking as the primary product model.
- Do not add nearest-driver taxi dispatch, surge pricing, or taxi-meter behavior unless LATRA explicitly requires it for Rishfy's licensed category.
- Where a LATRA phrase assumes taxi-style hailing, document the Rishfy adaptation and show the equivalent safety/audit outcome.
