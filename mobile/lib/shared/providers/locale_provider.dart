import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

/// Current app locale. Persisted via SharedPreferences.
final StateNotifierProvider<LocaleNotifier, Locale> localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale>(
  (Ref ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString(AppConstants.keyLocale);
    if (saved != null) {
      state = Locale(saved);
    }
  }

  Future<void> setLocale(String languageCode) async {
    state = Locale(languageCode);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyLocale, languageCode);
  }

  /// Toggle between English and Swahili.
  Future<void> toggle() async {
    await setLocale(state.languageCode == 'en' ? 'sw' : 'en');
  }
}

/// Currently-active role for users who are both passenger and driver.
/// Default: 'passenger'. Changed from the home screen's role switcher.
final StateProvider<String> activeRoleProvider = StateProvider<String>(
  (Ref ref) => 'passenger',
);
