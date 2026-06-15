import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/dio_client.dart';

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
  final String normalized = type.trim().toLowerCase().replaceAll('.', '_');
  if (normalized.startsWith('booking_')) return NotificationCategory.bookings;
  if (normalized.startsWith('trip_') ||
      normalized.contains('journey') ||
      normalized.contains('boarded') ||
      normalized.contains('dropoff') ||
      normalized.contains('arrived')) {
    return NotificationCategory.trips;
  }
  if (normalized.startsWith('payment_') ||
      normalized.contains('refund') ||
      normalized.contains('payout') ||
      normalized.contains('settlement')) {
    return NotificationCategory.payments;
  }
  if (normalized.startsWith('promo_') || normalized.startsWith('marketing_')) {
    return NotificationCategory.promotions;
  }
  return NotificationCategory.system;
}

bool isCriticalNotificationType(String type) {
  final String normalized = type.trim().toLowerCase().replaceAll('.', '_');
  return normalized.contains('emergency') ||
      normalized.contains('sos') ||
      normalized.contains('safety') ||
      normalized.contains('no_show') ||
      normalized.startsWith('system_critical');
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
  (Ref ref) => NotificationPreferencesNotifier(ref.read(dioClientProvider)),
);

class NotificationPreferencesNotifier
    extends StateNotifier<NotificationPreferences> {
  NotificationPreferencesNotifier(this._dio)
      : super(NotificationPreferences(<NotificationCategory, bool>{})) {
    unawaited(_load());
  }

  final Dio _dio;

  Future<void> _load() async {
    try {
      final Response<Map<String, dynamic>> response =
          await _dio.get<Map<String, dynamic>>(
        '/api/v1/notifications/preferences',
      );
      final List<dynamic> raw =
          response.data?['preferences'] as List<dynamic>? ?? <dynamic>[];
      final Map<NotificationCategory, bool> remote =
          <NotificationCategory, bool>{};
      for (final dynamic item in raw) {
        if (item is! Map) continue;
        final String? category = item['category'] as String?;
        final NotificationCategory? parsed = _categoryFromKey(category);
        if (parsed != null) {
          remote[parsed] = item['enabled'] as bool? ?? true;
        }
      }
      if (remote.isNotEmpty) {
        state = NotificationPreferences(remote);
        await _persistLocal(remote);
        return;
      }
    } catch (_) {}

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
    try {
      await _dio.put<void>(
        '/api/v1/notifications/preferences/${c.key}',
        data: <String, dynamic>{'enabled': value},
      );
    } catch (_) {}
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kPrefix${c.key}', value);
  }

  Future<void> _persistLocal(Map<NotificationCategory, bool> values) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final MapEntry<NotificationCategory, bool> entry in values.entries) {
      await prefs.setBool('$_kPrefix${entry.key.key}', entry.value);
    }
  }
}

NotificationCategory? _categoryFromKey(String? key) {
  for (final NotificationCategory category in NotificationCategory.values) {
    if (category.key == key) return category;
  }
  return null;
}
