import '../../auth/domain/entities/user.dart';
import '../../routes/data/models/route_models.dart';

class PublicDriverProfile {
  const PublicDriverProfile({
    required this.user,
    this.driverProfile,
    this.activeVehicle,
    this.vehicles = const <DriverVehicleOption>[],
    this.reviews = const <DriverReview>[],
  });

  final User user;
  final DriverProfileSummary? driverProfile;
  final DriverVehicleOption? activeVehicle;
  final List<DriverVehicleOption> vehicles;
  final List<DriverReview> reviews;
}

class DriverProfileSummary {
  const DriverProfileSummary({
    required this.isVerified,
    this.licenseExpiry,
    this.verifiedAt,
    this.latraPermitNumber,
  });

  final bool isVerified;
  final DateTime? licenseExpiry;
  final DateTime? verifiedAt;
  final String? latraPermitNumber;
}

class DriverReview {
  const DriverReview({
    required this.ratingId,
    required this.score,
    required this.createdAt,
    this.comment,
  });

  final String ratingId;
  final int score;
  final String? comment;
  final DateTime createdAt;
}
