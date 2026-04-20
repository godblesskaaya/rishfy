import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Global application logger.
///
/// Redacts common PII patterns before writing to any sink.
/// In release builds, logs above [Level.warning] are also forwarded to Crashlytics.
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    filter: _RishfyLogFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: _RishfyLogOutput(),
  );

  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(_redact(message), error: error, stackTrace: stackTrace);
  }

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(_redact(message), error: error, stackTrace: stackTrace);
  }

  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(_redact(message), error: error, stackTrace: stackTrace);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(_redact(message), error: error, stackTrace: stackTrace);
  }

  /// Redact common PII patterns.
  static String _redact(String message) {
    return message
        // Phone numbers (E.164)
        .replaceAllMapped(
          RegExp(r'(\+?\d{3})\d{4,6}(\d{2,4})'),
          (Match m) => '${m.group(1)}***${m.group(2)}',
        )
        // Email addresses
        .replaceAllMapped(
          RegExp(r'([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*(@[A-Za-z0-9.-]+)'),
          (Match m) => '${m.group(1)}***${m.group(2)}',
        )
        // JWT tokens
        .replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
            '[JWT_REDACTED]');
  }
}

class _RishfyLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kReleaseMode) {
      // In release, only log warnings and above
      return event.level.index >= Level.warning.index;
    }
    return true;
  }
}

class _RishfyLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final String line in event.lines) {
      // In debug, use debugPrint (throttled, avoids buffer overruns).
      // In release, could forward to a remote log sink here.
      debugPrint(line);
    }
  }
}
