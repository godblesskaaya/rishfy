import '../../auth/domain/entities/user.dart';

class FavoriteDriver {
  const FavoriteDriver({
    required this.id,
    required this.driverUserId,
    required this.createdAt,
    this.driver,
  });

  final String id;
  final String driverUserId;
  final DateTime createdAt;
  final User? driver;

  String get displayName {
    final String name = driver?.fullName.trim() ?? '';
    if (name.isNotEmpty) return name;
    final int end = driverUserId.length < 8 ? driverUserId.length : 8;
    return 'Driver ${driverUserId.substring(0, end)}';
  }

  double get ratingAverage => driver?.ratingAverage ?? 0;
  int get ratingCount => driver?.ratingCount ?? 0;
}
