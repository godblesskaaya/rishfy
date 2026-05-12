import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

const String _kThemeModeKey = 'theme_mode';

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

/// Theme mode (system / light / dark). Persisted via SharedPreferences.
final StateNotifierProvider<ThemeModeNotifier, ThemeMode> themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (Ref ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString(_kThemeModeKey);
    state = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }
}
