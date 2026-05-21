# Rishfy Trip Management Specification

## 1. Purpose

This document defines the trip-management model that begins **after a passenger selects a matched route**.

It extends [route-matching-spec.md](C:/Users/Hp/Documents/GitHub/rishfy/docs/route-matching-spec.md) by defining:

- passenger and driver trip-management responsibilities
- lifecycle states after booking confirmation
- backend contracts and event needs
- frontend experiences for each trip phase

This specification preserves the route-matching core principle:

> The driver's route is fixed. The passenger joins and exits that fixed route at computed pickup and dropoff points.

Trip management must therefore model **a passenger journey attached to a fixed driver route**, not just a single generic "active trip" state.

---

## 2. Core Principle

### 2.1 Journey Model

For a matched booking, the passenger experience consists of four legs:

1. Walk from passenger origin to the suggested pickup point on the route
2. Wait for and meet the driver at that pickup point
3. Travel in-vehicle along the relevant segment of the driver's fixed route
4. Walk from the computed dropoff point on the route to the passenger's final destination

The driver, meanwhile, continues operating their fixed route and manages passenger-specific operational moments on top of it.

### 2.2 Consequence

The passenger lifecycle is **not identical** to the driver's route lifecycle.

One driver route may have:

- multiple passengers
- different pickup points
- different dropoff points
- different boarding and alighting times

The system must therefore support:

- a **driver operational state**
- a **passenger booking journey state**

These two lifecycles are related but not the same.

---

## 3. Existing Inputs From Route Matching

The route-matching flow already produces key trip-management inputs:

- fixed driver route polyline
- suggested pickup point on the route
- suggested dropoff point on the route
- walking distance/time to pickup
- walking distance/time from dropoff
- estimated pickup time

These outputs should become first-class inputs into trip management, not just booking metadata.

---

## 4. Trip Actors

### 4.1 Passenger

The passenger needs to:

- understand where to walk for pickup
- know when the driver is approaching
- know when the driver has arrived
- confirm progress through their own journey
- receive guidance after dropoff

### 4.2 Driver

The driver needs to:

- see passenger pickup and dropoff points along the fixed route
- understand which passenger action is next
- update passenger-specific operational states
- continue navigation along the fixed route without detour confusion

### 4.3 System

The system needs to:

- reconcile driver movement against fixed-route geometry
- compute ETA and proximity to pickup/dropoff points
- emit trip events tied to a booking journey
- provide dedicated frontend experiences for both roles

---

## 5. Lifecycle Model

## 5.1 Driver Route Operational State

This is the high-level state of the driver on a route instance.

- `scheduled`
- `departed`
- `active`
- `completed`
- `cancelled`

This state is route-centric and should not be overloaded to describe each passenger's trip journey.

## 5.2 Passenger Booking Journey State

Each confirmed booking should move through the following lifecycle:

- `confirmed`
  - booking exists and is accepted
- `walking_to_pickup`
  - passenger is navigating to the suggested pickup point
- `waiting_for_driver`
  - passenger is at or near pickup and waiting
- `driver_approaching`
  - driver is on route and nearing the pickup point
- `driver_arrived`
  - driver is within arrival radius of the pickup point
- `boarded`
  - driver confirms passenger has entered the vehicle
- `in_transit`
  - passenger is currently riding
- `approaching_dropoff`
  - driver is nearing passenger dropoff point
- `dropped_off`
  - driver confirms passenger has exited the vehicle
- `walking_to_destination`
  - passenger is navigating from route dropoff point to final destination
- `completed`
  - passenger journey is fully complete
- `cancelled`
  - booking cancelled before boarding
- `no_show`
  - passenger or driver no-show outcome

### 5.3 Why This Split Matters

Example:

- driver route is active for 45 minutes
- passenger A boards at minute 8 and exits at minute 18
- passenger B boards at minute 20 and exits at minute 35

The driver's route is one continuous operation.
The passengers have separate booking journeys.

---

## 6. State Ownership

### 6.1 Driver-controlled transitions

The driver should be able to trigger:

- `departed`
- `driver_arrived`
- `boarded`
- `dropped_off`
- `no_show`

These transitions should be scoped to a specific booking when relevant.

### 6.2 System-controlled transitions

The system should be able to infer or suggest:

- `driver_approaching`
- `driver_arrived` candidate
- `approaching_dropoff`

These are typically proximity-based and should be derived from live location vs booking pickup/dropoff geometry.

### 6.3 Passenger-controlled transitions

The passenger may optionally confirm:

- `walking_to_pickup`
- `waiting_for_driver`
- `walking_to_destination`

Passenger confirmation is useful for UX and support context, but should not be the only source of truth for operational states.

---

## 7. Frontend Experience Requirements

## 7.1 Passenger Experience

The passenger should not see a generic "track trip" screen for the entire lifecycle.

They need dedicated screens or screen states for:

### A. Before pickup

- suggested pickup point on map
- walking route from current location to pickup point
- walking ETA and distance
- driver profile and vehicle details
- estimated driver arrival time at pickup point
- clear state: `walk now`, `wait`, or `driver approaching`

### B. Driver approaching

- live driver location on fixed route
- ETA from driver to pickup point
- pickup point highlighted
- arrival notifications

### C. In vehicle

- current driver location
- fixed route polyline
- passenger dropoff point on route
- ETA to dropoff

### D. After dropoff

- walking route from dropoff point to final destination
- walking ETA and distance
- trip completion confirmation
- rating flow

## 7.2 Driver Experience

The driver active-route experience should prioritize:

- current fixed route
- upcoming passenger stop
- passenger pickup point on route
- passenger dropoff point on route
- primary next action

Driver actions should be explicit and booking-specific:

- `Arrived at pickup`
- `Passenger boarded`
- `Passenger dropped off`
- `Mark no-show`

If multiple passengers exist on a route, the UI should make the next operational stop obvious.

## 7.3 Shared Experience Rules

- pickup and dropoff points should be represented as **route-relative stops**
- live ETA should clearly indicate whether it is estimated from current traffic, route geometry, or straight-line fallback
- a passenger should never have to infer whether they are still walking, waiting, riding, or post-dropoff

---

## 8. Backend Contract Requirements

## 8.1 New Booking Journey Actions

The backend should support booking-scoped trip actions such as:

- `POST /bookings/{id}/arrive-pickup`
- `POST /bookings/{id}/board-passenger`
- `POST /bookings/{id}/dropoff-passenger`
- `POST /bookings/{id}/mark-no-show`

These are booking-journey actions, not route-level actions.

## 8.2 Live Trip Context

For each active booking journey, backend responses should provide:

- booking journey state
- pickup point coordinates and human-readable label
- dropoff point coordinates and human-readable label
- route polyline
- current driver location
- ETA to pickup or dropoff as relevant
- whether ETA is stale or approximate

## 8.3 Walking Navigation Support

Trip management should expose dedicated walking-leg data for:

- passenger origin -> suggested pickup point
- route dropoff point -> passenger destination

At minimum, backend should support:

- walking distance
- walking duration
- optional encoded polyline

Preferred future support:

- step-by-step maneuver instructions

## 8.4 Event Model

The system should publish booking-journey events such as:

- `booking.journey_started`
- `driver.approaching_pickup`
- `driver.arrived_pickup`
- `passenger.boarded`
- `driver.approaching_dropoff`
- `passenger.dropped_off`
- `passenger.walking_to_destination`
- `booking.journey_completed`
- `booking.no_show`

Events must include enough context for notification and mobile app hydration:

- booking ID
- route ID
- driver ID
- passenger ID
- trip ID
- pickup/dropoff point
- timestamp

## 8.5 Location Requirements

Live location contracts should support:

- reliable driver identity binding
- booking-aware trip context
- trip trace storage linked to trip ID
- ETA computation against pickup/dropoff points
- proximity detection for pickup and dropoff

If passenger live sharing is a product requirement, a separate passenger-location contract must be defined explicitly instead of being inferred from driver tracking.

---

## 9. Frontend Gaps

- No dedicated passenger journey lifecycle in the mobile app
- No walking-to-pickup navigation experience
- No walking-from-dropoff navigation experience
- No driver-facing booking-journey controls such as arrived/boarded/dropped-off
- No clear distinction between driver route state and passenger journey state
- No route-relative stop management UI for multiple passengers
- No passenger-facing ETA to pickup point from live driver position
- No clear post-dropoff journey continuation

---

## 10. Backend Gaps

- Booking lifecycle is too coarse for passenger journey management
- No implemented booking-scoped trip state machine beyond start/complete
- No booking-journey action endpoints for arrival, boarding, or dropoff
- No dedicated trip-management response model combining route geometry, live location, ETA, and booking stop context
- No walking-leg polyline/navigation contract for pickup and post-dropoff legs
- Arrival detection and notifications are not yet rich enough to support booking-journey state cleanly
- Live location contracts are inconsistent with current mobile payload usage
- Trip trace linkage and trip-aware location recording need stronger end-to-end wiring

---

## 11. MVP Recommendation

### Phase 1

Implement the minimum viable passenger journey lifecycle:

- `confirmed`
- `driver_approaching`
- `driver_arrived`
- `boarded`
- `in_transit`
- `dropped_off`
- `walking_to_destination`
- `completed`

### Phase 2

Add richer assistance:

- walking polylines for pickup/dropoff legs
- route-aware ETA updates
- multiple-passenger stop sequencing for drivers
- no-show workflows

### Phase 3

Add advanced operational features:

- passenger live-share to driver
- proactive reminders for walking to pickup
- support tooling around missed pickups and disputed handoffs

---

## 12. Non-Goals

This specification does not change the route-matching principle by default.

Specifically, it does not assume:

- driver detours off their fixed route
- door-to-door pickup by the driver
- a single undifferentiated trip lifecycle for all passengers on a route

Any future detour model should be introduced as a separate product capability.

---

## 13. Summary

Route matching already defines the important geometry:

- where the passenger joins the route
- where the passenger exits the route
- how long they walk before and after the ride
- when the driver is expected to reach the pickup point

Trip management should operationalize those outputs into a passenger-centric journey lifecycle and a driver-facing stop-management workflow.

The core product is therefore:

> A passenger joins and exits a fixed driver route through managed pickup and dropoff rendezvous, with walking guidance before boarding and after alighting.
