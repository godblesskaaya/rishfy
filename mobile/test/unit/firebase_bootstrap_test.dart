import 'package:flutter_test/flutter_test.dart';
import 'package:rishfy/core/config/env.dart';
import 'package:rishfy/core/config/firebase_bootstrap.dart';

void main() {
  group('isFirebaseEnabledForCurrentEnv', () {
    test('returns false when analytics and crash reporting are disabled',
        () async {
      await Env.load();

      expect(isFirebaseEnabledForCurrentEnv(), isFalse);
    });
  });

  group('initializeFirebaseIfConfigured', () {
    test('skips initializer when Firebase is disabled for the environment',
        () async {
      await Env.load();

      var called = false;

      final bool initialized = await initializeFirebaseIfConfigured(
        initializeApp: ({String? name, options}) async {
          called = true;
          throw StateError('initializer should not be called');
        },
      );

      expect(initialized, isFalse);
      expect(called, isFalse);
    });
  });
}
