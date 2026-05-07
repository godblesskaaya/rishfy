import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rishfy/features/auth/domain/entities/user.dart';
import 'package:rishfy/features/auth/domain/repositories/auth_repository.dart';
import 'package:rishfy/features/auth/presentation/providers/auth_provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockRepo;

  setUpAll(() {
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

  group('AuthController.login', () {
    test('transitions to authenticated on success', () async {
      when(() => mockRepo.getCurrentSession()).thenAnswer((_) async => null);
      when(
        () => mockRepo.login(
          identifier: any(named: 'identifier'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => _fakeSession());

      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).login(
            identifier: '+255712345678',
            password: 'Password123',
          );

      final AuthState state = container.read(authControllerProvider).value!;
      expect(state.isAuthenticated, isTrue);
      expect(state.user?.userId, equals('user-123'));
    });
  });

  group('AuthController.register', () {
    test('returns pending registration details without authenticating', () async {
      when(() => mockRepo.getCurrentSession()).thenAnswer((_) async => null);
      when(
        () => mockRepo.register(
          phoneNumber: any(named: 'phoneNumber'),
          password: any(named: 'password'),
          fullName: any(named: 'fullName'),
          email: any(named: 'email'),
        ),
      ).thenAnswer((_) async => const PendingRegistration(
            userId: 'pending-user',
            phoneNumber: '+255712345678',
          ));

      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);

      final PendingRegistration pending =
          await container.read(authControllerProvider.notifier).register(
                phoneNumber: '+255712345678',
                password: 'Password123',
                fullName: 'Test User',
                email: 'test@example.com',
              );

      expect(pending.userId, equals('pending-user'));
      expect(
        container.read(authControllerProvider).value?.isAuthenticated,
        isFalse,
      );
    });
  });

  group('AuthController.verifyOtp', () {
    test('transitions to authenticated after registration verification', () async {
      when(() => mockRepo.getCurrentSession()).thenAnswer((_) async => null);
      when(
        () => mockRepo.verifyOtp(
          userId: any(named: 'userId'),
          otpCode: any(named: 'otpCode'),
        ),
      ).thenAnswer((_) async => _fakeSession());

      final ProviderContainer container = makeContainer();
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).verifyOtp(
            userId: 'pending-user',
            otpCode: '123456',
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
