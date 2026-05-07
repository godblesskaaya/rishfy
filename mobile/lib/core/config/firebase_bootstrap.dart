import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_logger.dart';
import 'env.dart';

typedef FirebaseInitializer = Future<FirebaseApp> Function(
    {String? name, FirebaseOptions? options});

bool isFirebaseEnabledForCurrentEnv() {
  return !kIsWeb && (Env.enableAnalytics || Env.enableCrashReporting);
}

Future<bool> initializeFirebaseIfConfigured({
  FirebaseInitializer initializeApp = Firebase.initializeApp,
}) async {
  if (!isFirebaseEnabledForCurrentEnv()) {
    AppLogger.info(
      'Firebase disabled for ${Env.environment}; skipping initialization',
    );
    return false;
  }

  try {
    await initializeApp();
    AppLogger.info('Firebase initialized for ${Env.environment}');
    return true;
  } catch (error, stackTrace) {
    AppLogger.warn(
      'Firebase initialization skipped because native config is missing or invalid.',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}
