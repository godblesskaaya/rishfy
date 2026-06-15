class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.blockedUserId,
    required this.createdAt,
    this.reason,
    this.displayNameOverride,
    this.role,
    this.ratingAverage,
    this.ratingCount,
  });

  final String id;
  final String blockedUserId;
  final String? reason;
  final DateTime createdAt;
  final String? displayNameOverride;
  final String? role;
  final double? ratingAverage;
  final int? ratingCount;

  String get displayName {
    final String name = displayNameOverride?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final int end = blockedUserId.length < 8 ? blockedUserId.length : 8;
    return 'User ${blockedUserId.substring(0, end)}';
  }
}
