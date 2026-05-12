import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-facing notification categories. Each maps to a set of backend
/// notification `type` values produced by the notification service.
enum NotificationCategory {
  bookings,
  trips,
  payments,
  promotions,
  system,
}

extension NotificationCategoryX on NotificationCategory {
  String get key {
    switch (this) {
      case NotificationCategory.bookings:
        return 'bookings';
      case NotificationCategory.trips:
        return 'trips';
      case NotificationCategory.payments:
        return 'payments';
      case NotificationCategory.promotions:
        return 'promotions';
      case NotificationCategory.system:
        return 'system';
    }
  }

  String get label {
    switch (this) {
      case NotificationCategory.bookings:
        return 'Bookings';
      case NotificationCategory.trips:
        return 'Trips';
      case NotificationCategory.payments:
        return 'Payments';
      case NotificationCategory.promotions:
        return 'Promotions & offers';
      case NotificationCategory.system:
        return 'System messages';
    }
  }

  String get description {
    switch (this) {
      case NotificationCategory.bookings:
        return 'Confirmations, cancellations, decline windows';
      case NotificationCategory.trips:
        return 'Trip started, en route, completed';
      case NotificationCategory.payments:
        return 'Payment confirmations and failures';
      case NotificationCategory.promotions:
        return 'Discounts and announcements';
      case NotificationCategory.system:
        return 'Account & security notices';
    }
  }
}

/// Map a notification type from the backend to a category. Anything we don't
/// recognise falls into [NotificationCategory.system].
NotificationCategory categoryFor(String type) {
  if (type.startsWith('booking_')) return NotificationCategory.bookings;
  if (type.startsWith('trip_')) return NotificationCategory.trips;
  if (type.startsWith('payment_')) return NotificationCategory.payments;
  if (type.startsWith('promo_') || type.startsWith('marketing_')) {
    return NotificationCategory.promotions;
  }
  return NotificationCategory.system;
}

const String _kPrefix = 'notif_pref_';

class NotificationPreferences {
  const NotificationPreferences(this._enabled);
  final Map<NotificationCategory, bool> _enabled;

  bool isEnabled(NotificationCategory c) => _enabled[c] ?? true;

  NotificationPreferences copyWith(NotificationCategory c, bool value) {
    final Map<NotificationCategory, bool> next =
        Map<NotificationCategory, bool>.from(_enabled);
    next[c] = value;
    return NotificationPreferences(next);
  }
}

final StateNotifierProvider<NotificationPreferencesNotifier,
        NotificationPreferences> notificationPreferencesProvider =
    StateNotifierProvider<NotificationPreferencesNotifier,
        NotificationPreferences>(
  (Ref ref) => NotificationPreferencesNotifier(),
);

class NotificationPreferencesNotifier
    extends StateNotifier<NotificationPreferences> {
  NotificationPreferencesNotifier()
      : super(NotificationPreferences(<NotificationCategory, bool>{})) {
    unawaited(_load());
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<NotificationCategory, bool> map =
        <NotificationCategory, bool>{};
    for (final NotificationCategory c in NotificationCategory.values) {
      map[c] = prefs.getBool('$_kPrefix${c.key}') ?? true;
    }
    state = NotificationPreferences(map);
  }

  Future<void> setEnabled(NotificationCategory c, bool value) async {
    state = state.copyWith(c, value);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kPrefix${c.key}', value);
  }
}
