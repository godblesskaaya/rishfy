import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rishfy/features/auth/domain/entities/user.dart';
import 'package:rishfy/features/auth/domain/repositories/auth_repository.dart';
import 'package:rishfy/features/auth/presentation/providers/auth_provider.dart';

// =============================================================================
// Sample test — demonstrates patterns for the rest of the team to follow.
//
// Run with: flutter test test/unit/auth_controller_test.dart
// =============================================================================

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockRepo;

  setUpAll(() {
    // Register fallback values for any()-matched positional args.
    registerFallbackValue(UserRole.passenger);
  });

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  }

  group('AuthController.build', () {
    test('returns unauthenticated when no session exists', () async {
      when(() => mockRepo.getCurrentSession()).thenAnswer((_) async => null);

      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);

      final AuthState state = await container.read(authControllerProvider.future);

      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNull);
    });

    test('returns authenticated when session is persisted', () async {
      final AuthSession session = _fakeSession();
      when(() => mockRepo.getCurrentSession()).thenAnswer((_) async => session);

      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);

      final AuthState state = await container.read(authControllerProvider.future);

      expect(state.isAuthenticated, isTrue);
      expect(state.user?.userId, equals('user-123'));
    });
  });

  group('AuthController.loginWithOtp', () {
    test('transitions to authenticated on success', () async {
      when(() => mockRepo.getCurrentSession()).thenAnswer((_) async => null);
      when(() => mockRepo.verifyOtp(
            phoneNumber: any(named: 'phoneNumber'),
            otpCode: any(named: 'otpCode'),
            otpReference: any(named: 'otpReference'),
          )).thenAnswer((_) async => _fakeSession());

      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);

      // Wait for initial build
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).loginWithOtp(
            phoneNumber: '+255712345678',
            otpCode: '123456',
            otpReference: 'otp-ref',
          );

      final AuthState state = container.read(authControllerProvider).value!;
      expect(state.isAuthenticated, isTrue);
      expect(state.user?.userId, equals('user-123'));
    });
  });

  group('AuthController.logout', () {
    test('clears state and calls repository', () async {
      when(() => mockRepo.getCurrentSession())
          .thenAnswer((_) async => _fakeSession());
      when(() => mockRepo.logout()).thenAnswer((_) async {});

      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).logout();

      final AuthState state = container.read(authControllerProvider).value!;
      expect(state.isAuthenticated, isFalse);
      verify(() => mockRepo.logout()).called(1);
    });
  });
}

// =============================================================================
// Test fixtures
// =============================================================================

AuthSession _fakeSession() {
  return AuthSession(
    accessToken: 'fake-access-token',
    refreshToken: 'fake-refresh-token',
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    user: const User(
      userId: 'user-123',
      phoneNumber: '+255712345678',
      firstName: 'Test',
      lastName: 'User',
      role: UserRole.passenger,
      isVerified: true,
    ),
  );
}
