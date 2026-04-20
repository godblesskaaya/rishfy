import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/otp_verification_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/bookings/presentation/screens/booking_detail_screen.dart';
import '../../features/bookings/presentation/screens/bookings_screen.dart';
import '../../features/bookings/presentation/screens/create_booking_screen.dart';
import '../../features/home/presentation/screens/driver_home_screen.dart';
import '../../features/home/presentation/screens/passenger_home_screen.dart';
import '../../features/home/presentation/screens/shell_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/routes/presentation/screens/post_route_screen.dart';
import '../../features/routes/presentation/screens/route_detail_screen.dart';
import '../../features/routes/presentation/screens/route_search_screen.dart';
import '../../features/trip/presentation/screens/active_trip_screen.dart';
import '../../shared/providers/locale_provider.dart';

part 'app_router.g.dart';

/// Root navigator keys — expose for nested navigators if needed.
final GlobalKey<NavigatorState> _rootNavKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavKey =
    GlobalKey<NavigatorState>(debugLabel: 'shell');

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) {
  final AsyncValue<AuthState> auth = ref.watch(authControllerProvider);

  return GoRouter(
    navigatorKey: _rootNavKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    refreshListenable: _AuthNotifier(ref),
    redirect: (BuildContext context, GoRouterState state) {
      final bool isAuthed = auth.maybeWhen(
        data: (AuthState s) => s.isAuthenticated,
        orElse: () => false,
      );

      final bool loading = auth.isLoading || auth is AsyncLoading;
      final String path = state.matchedLocation;

      // Let splash handle its own redirect
      if (path == '/splash') return null;

      final bool onAuthRoute = path.startsWith('/auth') ||
          path == '/login' ||
          path == '/register' ||
          path == '/onboarding';

      // Not authenticated → force onto auth flow
      if (!isAuthed && !loading && !onAuthRoute) {
        return '/login';
      }

      // Already authenticated → skip auth screens
      if (isAuthed && onAuthRoute) {
        return '/home';
      }

      return null; // No redirect
    },
    routes: <RouteBase>[
      // ---- Bootstrap & Auth (outside shell) ----
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra as Map<String, dynamic>?;
          return OtpVerificationScreen(
            phoneNumber: extra?['phoneNumber'] as String? ?? '',
            otpReference: extra?['otpReference'] as String? ?? '',
            purpose: extra?['purpose'] as String? ?? 'registration',
          );
        },
      ),

      // ---- Main shell (bottom navigation) ----
      ShellRoute(
        navigatorKey: _shellNavKey,
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return ShellScreen(child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/home',
            pageBuilder: (BuildContext context, GoRouterState state) {
              final String role = ref.watch(activeRoleProvider);
              return NoTransitionPage<void>(
                child: role == 'driver'
                    ? const DriverHomeScreen()
                    : const PassengerHomeScreen(),
              );
            },
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (_, __) => const NoTransitionPage<void>(
              child: RouteSearchScreen(),
            ),
          ),
          GoRoute(
            path: '/bookings',
            pageBuilder: (_, __) => const NoTransitionPage<void>(
              child: BookingsScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) => const NoTransitionPage<void>(
              child: ProfileScreen(),
            ),
          ),
        ],
      ),

      // ---- Feature routes (outside shell, full screen) ----
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/routes/post',
        builder: (_, __) => const PostRouteScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/routes/:routeId',
        builder: (BuildContext context, GoRouterState state) {
          return RouteDetailScreen(
            routeId: state.pathParameters['routeId']!,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/bookings/create',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra as Map<String, dynamic>?;
          return CreateBookingScreen(
            routeId: extra?['routeId'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/bookings/:bookingId',
        builder: (BuildContext context, GoRouterState state) {
          return BookingDetailScreen(
            bookingId: state.pathParameters['bookingId']!,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/trip/:bookingId',
        builder: (BuildContext context, GoRouterState state) {
          return ActiveTripScreen(
            bookingId: state.pathParameters['bookingId']!,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavKey,
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Page not found: ${state.matchedLocation}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
    },
  );
});

/// Bridge between Riverpod's AuthState changes and go_router's refreshListenable.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;
}
