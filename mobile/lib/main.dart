import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/constants/app_logger.dart';

Future<void> main() async {
  // Run in a guarded zone to capture all async errors
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Lock to portrait for v1
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Load environment config (dev/staging/prod selected at build time)
    await Env.load();

    // Firebase (skip on web for now)
    if (!kIsWeb) {
      await Firebase.initializeApp();

      if (kReleaseMode) {
        // Forward Flutter errors to Crashlytics in release builds
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
      }
    }

    // Global error logger
    FlutterError.onError = (FlutterErrorDetails details) {
      AppLogger.error(
        'Flutter framework error',
        error: details.exception,
        stackTrace: details.stack,
      );
      if (kReleaseMode) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    runApp(
      const ProviderScope(
        child: RishfyApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    AppLogger.error('Uncaught zone error', error: error, stackTrace: stack);
    if (kReleaseMode) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}
