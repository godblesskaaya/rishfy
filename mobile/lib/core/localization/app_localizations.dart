import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

/// Placeholder [AppLocalizations] class until the real generated file lands.
/// Replace this with Flutter's standard l10n generation (see:
/// https://docs.flutter.dev/accessibility-and-localization/internationalization).
///
/// This stub lets the app compile and tests pass while l10n is being set up.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('sw'),
  ];

  static const Map<String, Map<String, String>> _translations =
      <String, Map<String, String>>{
    'en': <String, String>{
      'app_name': 'Rishfy',
      'welcome': 'Welcome to Rishfy',
      'login': 'Log in',
      'register': 'Sign up',
      'logout': 'Log out',
      'phone_number': 'Phone number',
      'enter_phone': 'Enter your phone number',
      'verify': 'Verify',
      'resend_otp': 'Resend code',
      'home': 'Home',
      'search': 'Search',
      'bookings': 'Bookings',
      'profile': 'Profile',
      'driver_mode': 'Driver mode',
      'passenger_mode': 'Passenger mode',
      'post_route': 'Post a route',
      'search_routes': 'Search routes',
      'from': 'From',
      'to': 'To',
      'departure': 'Departure',
      'seats': 'Seats',
      'price_per_seat': 'Price per seat',
      'book_now': 'Book now',
      'confirm': 'Confirm',
      'cancel': 'Cancel',
      'save': 'Save',
      'loading': 'Loading...',
      'error_generic': 'Something went wrong. Please try again.',
      'error_no_connection': 'No internet connection.',
      'error_timeout': 'Request timed out.',
    },
    'sw': <String, String>{
      'app_name': 'Rishfy',
      'welcome': 'Karibu Rishfy',
      'login': 'Ingia',
      'register': 'Jisajili',
      'logout': 'Toka',
      'phone_number': 'Namba ya simu',
      'enter_phone': 'Weka namba yako ya simu',
      'verify': 'Thibitisha',
      'resend_otp': 'Tuma tena',
      'home': 'Nyumbani',
      'search': 'Tafuta',
      'bookings': 'Safari zangu',
      'profile': 'Wasifu',
      'driver_mode': 'Hali ya dereva',
      'passenger_mode': 'Hali ya abiria',
      'post_route': 'Weka safari',
      'search_routes': 'Tafuta safari',
      'from': 'Kutoka',
      'to': 'Kwenda',
      'departure': 'Kuondoka',
      'seats': 'Viti',
      'price_per_seat': 'Bei kwa kiti',
      'book_now': 'Kata tiketi',
      'confirm': 'Thibitisha',
      'cancel': 'Ghairi',
      'save': 'Hifadhi',
      'loading': 'Inapakia...',
      'error_generic': 'Hitilafu imetokea. Jaribu tena.',
      'error_no_connection': 'Hakuna intaneti.',
      'error_timeout': 'Muda wa ombi umekwisha.',
    },
  };

  String t(String key) {
    return _translations[locale.languageCode]?[key] ??
        _translations['en']?[key] ??
        key;
  }

  // Currency formatting for TZS
  String formatTZS(int amount) {
    final NumberFormat formatter = NumberFormat('#,###', locale.toString());
    return '${formatter.format(amount)} TZS';
  }

  // Date formatting
  String formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy', locale.toString()).format(date);
  }

  String formatTime(DateTime time) {
    return DateFormat('HH:mm', locale.toString()).format(time);
  }

  String formatDateTime(DateTime dt) {
    return DateFormat('dd MMM, HH:mm', locale.toString()).format(dt);
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales
        .any((Locale l) => l.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
