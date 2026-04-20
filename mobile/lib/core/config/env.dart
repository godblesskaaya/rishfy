import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Environment configuration, loaded once at app start.
///
/// Build the app with the appropriate flavor:
///   flutter run --dart-define=ENV=dev
///   flutter build apk --dart-define=ENV=prod
///
/// Keys pulled from the corresponding assets/env/<env>.env file.
class Env {
  Env._();

  static late String _apiBaseUrl;
  static late String _wsBaseUrl;
  static late String _googleMapsApiKey;
  static late String _environment;
  static late bool _enableAnalytics;
  static late bool _enableCrashReporting;

  static String get apiBaseUrl => _apiBaseUrl;
  static String get wsBaseUrl => _wsBaseUrl;
  static String get googleMapsApiKey => _googleMapsApiKey;
  static String get environment => _environment;
  static bool get enableAnalytics => _enableAnalytics;
  static bool get enableCrashReporting => _enableCrashReporting;

  static bool get isDev => _environment == 'dev';
  static bool get isStaging => _environment == 'staging';
  static bool get isProd => _environment == 'prod';

  static Future<void> load() async {
    const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
    _environment = env;

    // Load the matching env file from assets.
    // Fallback to hardcoded defaults in debug mode so fresh checkouts work.
    Map<String, String> values = <String, String>{};
    try {
      final String raw =
          await rootBundle.loadString('assets/env/$env.env');
      values = _parseEnv(raw);
    } catch (_) {
      if (kDebugMode) {
        debugPrint('⚠️  No env file for "$env", using dev defaults');
      }
      values = _devDefaults();
    }

    _apiBaseUrl = values['API_BASE_URL'] ?? 'http://10.0.2.2';
    _wsBaseUrl = values['WS_BASE_URL'] ?? 'ws://10.0.2.2/ws';
    _googleMapsApiKey = values['GOOGLE_MAPS_API_KEY'] ?? '';
    _enableAnalytics = values['ENABLE_ANALYTICS'] == 'true';
    _enableCrashReporting = values['ENABLE_CRASH_REPORTING'] == 'true';
  }

  /// Development defaults — matches docker-compose stack on host machine.
  /// 10.0.2.2 is Android emulator's alias for host's localhost.
  /// For iOS simulator, use 'localhost' instead.
  static Map<String, String> _devDefaults() {
    return <String, String>{
      'API_BASE_URL': 'http://10.0.2.2',
      'WS_BASE_URL': 'ws://10.0.2.2/ws',
      'GOOGLE_MAPS_API_KEY': '',
      'ENABLE_ANALYTICS': 'false',
      'ENABLE_CRASH_REPORTING': 'false',
    };
  }

  static Map<String, String> _parseEnv(String raw) {
    final Map<String, String> result = <String, String>{};
    for (final String line in raw.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final int eq = trimmed.indexOf('=');
      if (eq < 0) {
        continue;
      }
      final String key = trimmed.substring(0, eq).trim();
      final String value = trimmed.substring(eq + 1).trim();
      result[key] = value;
    }
    return result;
  }
}
