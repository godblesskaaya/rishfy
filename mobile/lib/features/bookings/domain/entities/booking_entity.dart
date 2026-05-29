import 'package:equatable/equatable.dart';

class BookingEntity extends Equatable {
  const BookingEntity({
    required this.bookingId,
    required this.routeId,
    required this.passengerUserId,
    required this.seatCount,
    required this.totalPriceTzs,
    required this.status,
    required this.paymentStatus,
    required this.createdAt,
    this.driverId,
    this.passengerName,
    this.confirmationCode,
    this.originName,
    this.destinationName,
    this.departureDatetime,
    this.driverName,
    this.vehiclePlate,
    this.paymentId,
    this.suggestedPickupName,
    this.pickupLat,
    this.pickupLng,
    this.suggestedDropoffName,
    this.dropoffPointLat,
    this.dropoffPointLng,
    this.destinationLat,
    this.destinationLng,
    this.tripId,
    this.journeyState,
    this.routeStatus,
    this.routePolyline,
    this.estimatedPickupTime,
    this.pickupWalkingDistance,
    this.pickupWalkingTime,
    this.dropoffWalkingDistance,
    this.dropoffWalkingTime,
    this.etaToPickupSeconds,
    this.etaToDropoffSeconds,
    this.etaUpdatedAt,
    this.etaApproximate,
    this.etaStale,
    this.driverLat,
    this.driverLng,
    this.driverHeading,
    this.driverSpeedKmh,
    this.driverLocationUpdatedAt,
    this.arrivedPickupAt,
    this.boardedAt,
    this.droppedOffAt,
    this.tripStartedAt,
    this.tripCompletedAt,
    this.journeyCompletedAt,
  });

  final String bookingId;
  final String routeId;
  final String passengerUserId;
  final int seatCount;
  final int totalPriceTzs;
  final String status;
  final String paymentStatus;
  final DateTime createdAt;
  final String? driverId;
  final String? passengerName;
  final String? confirmationCode;
  final String? originName;
  final String? destinationName;
  final DateTime? departureDatetime;
  final String? driverName;
  final String? vehiclePlate;
  final String? paymentId;
  final String? suggestedPickupName;
  final double? pickupLat;
  final double? pickupLng;
  final String? suggestedDropoffName;
  final double? dropoffPointLat;
  final double? dropoffPointLng;
  final double? destinationLat;
  final double? destinationLng;
  final String? tripId;
  final String? journeyState;
  final String? routeStatus;
  final String? routePolyline;
  final DateTime? estimatedPickupTime;
  final int? pickupWalkingDistance;
  final int? pickupWalkingTime;
  final int? dropoffWalkingDistance;
  final int? dropoffWalkingTime;
  final int? etaToPickupSeconds;
  final int? etaToDropoffSeconds;
  final DateTime? etaUpdatedAt;
  final bool? etaApproximate;
  final bool? etaStale;
  final double? driverLat;
  final double? driverLng;
  final double? driverHeading;
  final double? driverSpeedKmh;
  final DateTime? driverLocationUpdatedAt;
  final DateTime? arrivedPickupAt;
  final DateTime? boardedAt;
  final DateTime? droppedOffAt;
  final DateTime? tripStartedAt;
  final DateTime? tripCompletedAt;
  final DateTime? journeyCompletedAt;

  static const Set<String> _activeJourneyStates = <String>{
    'confirmed',
    'walking_to_pickup',
    'waiting_for_driver',
    'driver_approaching',
    'driver_arrived',
    'boarded',
    'in_transit',
    'approaching_dropoff',
    'dropped_off',
    'walking_to_destination',
  };

  String get normalizedStatus => status.trim().toLowerCase();

  String get effectiveJourneyState {
    final String? explicitJourneyState = _normalizeJourneyState(journeyState);
    if (explicitJourneyState != null) {
      return explicitJourneyState;
    }

    if (journeyCompletedAt != null) {
      return 'completed';
    }
    if (droppedOffAt != null || tripCompletedAt != null) {
      return 'walking_to_destination';
    }
    if (boardedAt != null || tripStartedAt != null) {
      return 'in_transit';
    }
    if (arrivedPickupAt != null) {
      return 'driver_arrived';
    }

    switch (normalizedStatus) {
      case 'active':
      case 'in_progress':
        return 'in_transit';
      case 'completed':
        return 'completed';
      case 'no_show':
        return 'no_show';
      case 'driver_cancelled':
      case 'passenger_cancelled':
      case 'cancelled':
      case 'declined':
        return 'cancelled';
      case 'pending':
        return 'pending';
      default:
        return normalizedStatus;
    }
  }

  String get effectiveRouteStatus {
    final String? normalizedRouteStatus =
        routeStatus?.trim().toLowerCase().replaceAll(' ', '_');
    if (normalizedRouteStatus != null && normalizedRouteStatus.isNotEmpty) {
      return normalizedRouteStatus;
    }
    if (isCompleted) {
      return 'completed';
    }
    if (isCancelled || isNoShow) {
      return 'cancelled';
    }
    if (isJourneyActive) {
      return 'active';
    }
    return 'scheduled';
  }

  bool get isPending => normalizedStatus == 'pending';
  bool get isCancelled =>
      const <String>{
        'cancelled',
        'driver_cancelled',
        'passenger_cancelled',
        'declined',
      }.contains(normalizedStatus) ||
      effectiveJourneyState == 'cancelled';
  bool get isNoShow =>
      normalizedStatus == 'no_show' || effectiveJourneyState == 'no_show';
  bool get isCompleted =>
      normalizedStatus == 'completed' || effectiveJourneyState == 'completed';
  bool get isJourneyActive =>
      _activeJourneyStates.contains(effectiveJourneyState);
  bool get isJourneyTrackable =>
      isJourneyActive ||
      driverLat != null ||
      driverLng != null ||
      const <String>{'completed', 'no_show'}.contains(effectiveJourneyState);
  bool get canOpenJourney => isJourneyTrackable || isJourneyActive;

  bool get isPrePickupJourney => const <String>{
        'confirmed',
        'walking_to_pickup',
        'waiting_for_driver',
        'driver_approaching',
        'driver_arrived',
      }.contains(effectiveJourneyState);

  bool get isInVehicleJourney => const <String>{
        'boarded',
        'in_transit',
        'approaching_dropoff',
      }.contains(effectiveJourneyState);

  bool get isPostDropoffJourney => const <String>{
        'dropped_off',
        'walking_to_destination',
        'completed',
      }.contains(effectiveJourneyState);

  bool get canDriverMarkArrived => const <String>{
        'driver_approaching',
      }.contains(effectiveJourneyState);
  bool get canDriverStartTrip => const <String>{
        'confirmed',
        'walking_to_pickup',
        'waiting_for_driver',
      }.contains(effectiveJourneyState);
  bool get canDriverMarkBoarded => const <String>{
        'driver_arrived',
      }.contains(effectiveJourneyState);
  bool get canDriverMarkDroppedOff => const <String>{
        'boarded',
        'in_transit',
        'approaching_dropoff'
      }.contains(effectiveJourneyState);
  bool get canDriverMarkNoShow => const <String>{
        'confirmed',
        'waiting_for_driver',
        'driver_arrived',
        'driver_approaching',
      }.contains(effectiveJourneyState);
  bool get canParticipantCompleteJourney => const <String>{
        'dropped_off',
        'walking_to_destination',
      }.contains(effectiveJourneyState);
  bool get hasPassengerIdentity =>
      passengerName != null && passengerName!.trim().isNotEmpty;

  String get pickupDisplayName =>
      suggestedPickupName ?? originName ?? 'Pickup point';

  String get dropoffDisplayName =>
      suggestedDropoffName ?? destinationName ?? 'Drop-off point';
  String get passengerDisplayName =>
      hasPassengerIdentity ? passengerName!.trim() : 'Passenger';

  double? get resolvedPickupLat => pickupLat;
  double? get resolvedPickupLng => pickupLng;
  double? get resolvedDropoffLat => dropoffPointLat ?? destinationLat;
  double? get resolvedDropoffLng => dropoffPointLng ?? destinationLng;
  String get journeyStreamId => tripId ?? bookingId;
  String get nextStopLabel =>
      isPrePickupJourney ? pickupDisplayName : dropoffDisplayName;

  String get nextDriverActionLabel {
    if (canDriverStartTrip) {
      return 'Start drive to pickup';
    }
    if (canDriverMarkArrived) {
      return 'Arrive at pickup';
    }
    if (canDriverMarkBoarded) {
      return 'Confirm boarding';
    }
    if (canDriverMarkDroppedOff) {
      return 'Confirm drop-off';
    }
    if (canParticipantCompleteJourney) {
      return 'Drop-off complete';
    }
    if (isCompleted) {
      return 'Journey completed';
    }
    return journeyLabel;
  }

  String get journeyLabel {
    switch (effectiveJourneyState) {
      case 'pending':
        return 'Awaiting payment';
      case 'confirmed':
        return 'Ready for pickup';
      case 'walking_to_pickup':
        return 'Walk to pickup';
      case 'waiting_for_driver':
        return 'Waiting for driver';
      case 'driver_approaching':
        return 'Driving to pickup';
      case 'driver_arrived':
        return 'Driver arrived';
      case 'boarded':
        return 'Passenger onboard';
      case 'in_transit':
        return 'In transit';
      case 'approaching_dropoff':
        return 'Approaching drop-off';
      case 'dropped_off':
        return 'Dropped off';
      case 'walking_to_destination':
        return 'Walk to destination';
      case 'completed':
        return 'Journey completed';
      case 'no_show':
        return 'No show';
      case 'cancelled':
        return 'Cancelled';
      default:
        return effectiveJourneyState.replaceAll('_', ' ');
    }
  }

  static String? _normalizeJourneyState(String? value) {
    if (value == null) {
      return null;
    }
    final String normalized = value.trim().toLowerCase().replaceAll(' ', '_');
    switch (normalized) {
      case 'active':
      case 'in_progress':
        return 'in_transit';
      case 'driver_arrived_pickup':
        return 'driver_arrived';
      case 'approaching_pickup':
        return 'driver_approaching';
      case 'approaching_destination':
        return 'approaching_dropoff';
      default:
        return normalized.isEmpty ? null : normalized;
    }
  }

  @override
  List<Object?> get props => <Object?>[
        bookingId,
        status,
        paymentStatus,
        passengerName,
        journeyState,
        routeStatus,
        tripId,
        pickupLat,
        pickupLng,
        dropoffPointLat,
        dropoffPointLng,
        estimatedPickupTime,
        destinationLat,
        destinationLng,
        etaToPickupSeconds,
        etaToDropoffSeconds,
        driverLat,
        driverLng,
        arrivedPickupAt,
        boardedAt,
        droppedOffAt,
        journeyCompletedAt,
      ];
}
