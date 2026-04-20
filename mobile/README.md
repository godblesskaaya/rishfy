# Rishfy Mobile App

> **Owner:** Fatma Abdallah (mobile lead) + whole team for feature work
> **Stack:** Flutter 3.22+ · Dart 3.4+ · Riverpod · go_router · Dio · Google Maps · Firebase

---

## Quick Start

```bash
# 1. Install Flutter SDK (>=3.22)
# https://docs.flutter.dev/get-started/install

# 2. Clone the repo and navigate
cd mobile

# 3. Install dependencies
flutter pub get

# 4. Generate code (Freezed, Riverpod, JSON)
dart run build_runner build --delete-conflicting-outputs

# 5. Run on emulator/device
flutter run --dart-define=ENV=dev
```

**Prerequisites for running the full stack locally:**

1. Backend Docker stack running: `./scripts/dev.sh up` (from repo root)
2. Google Maps API key in `assets/env/dev.env` (get from GCP Console)
3. Firebase project configured (see [Firebase setup](#firebase-setup) below)

---

## Architecture

We use **Clean Architecture** at the feature level: each feature has `data/`, `domain/`, and `presentation/` subdirs.

```
lib/
├── main.dart              Entry point — Zone-guarded, Crashlytics-wired
├── app.dart               Root MaterialApp.router + theme + l10n
│
├── core/                  Cross-cutting concerns (no feature logic)
│   ├── config/            Env loader (dev/staging/prod)
│   ├── constants/         App-wide constants + logger
│   ├── errors/            Typed AppException hierarchy
│   ├── localization/      English + Swahili translations
│   ├── network/           Dio client + 3 interceptors
│   ├── router/            go_router with auth guards
│   ├── storage/           flutter_secure_storage wrapper
│   └── theme/             Material 3 theme + semantic colors
│
├── features/              Feature modules (one per business capability)
│   ├── auth/              Login, register, OTP verification
│   ├── home/              Role-aware dashboard (passenger/driver)
│   ├── routes/            Search + post routes
│   ├── bookings/          Create, list, manage bookings
│   ├── trip/              Active trip with live tracking
│   ├── payments/          Mobile money flows
│   ├── profile/           User + settings
│   ├── notifications/     Inbox
│   └── vehicle/           Driver vehicle management
│
└── shared/                Reusable widgets + cross-feature providers
    ├── providers/
    └── widgets/
```

### State Management — Riverpod 2.5

We use **AsyncNotifierProvider** for controllers that load data, and **StateProvider** for simple mutable state (like the active role toggle).

```dart
// Example: auth controller
final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

// In UI:
final auth = ref.watch(authControllerProvider);
auth.when(
  data: (state) => HomeScreen(state),
  loading: () => const LoadingView(),
  error: (err, _) => ErrorView.fromException(err),
);
```

### Network — Dio + Interceptors

Request pipeline (in order):

1. **AuthInterceptor** — attaches JWT, refreshes on 401
2. **RetryInterceptor** — exponential backoff on transient errors
3. **ErrorInterceptor** — maps `DioException` → typed `AppException`
4. **PrettyDioLogger** (dev only) — pretty-prints requests/responses

All API calls go through `ref.read(dioClientProvider)`. Repositories are injected via Riverpod.

### Routing — go_router

`app_router.dart` defines the tree. Auth guards redirect unauthenticated users to `/login` and authenticated users away from auth screens.

Shell routes (`/home`, `/search`, `/bookings`, `/profile`) share the bottom nav. Full-screen routes (`/trip/:id`, `/bookings/:id`) sit outside the shell.

---

## Environments

Select at build time:

```bash
flutter run --dart-define=ENV=dev       # → assets/env/dev.env
flutter run --dart-define=ENV=staging   # → assets/env/staging.env
flutter build apk --dart-define=ENV=prod # → assets/env/prod.env
```

Env files live in `assets/env/`. Keys:

- `API_BASE_URL` — REST gateway endpoint
- `WS_BASE_URL` — WebSocket endpoint (live location stream)
- `GOOGLE_MAPS_API_KEY` — Google Maps SDK key
- `ENABLE_ANALYTICS` — Firebase Analytics toggle
- `ENABLE_CRASH_REPORTING` — Crashlytics toggle

**Note:** `10.0.2.2` is the Android emulator's alias for your host machine's localhost. For iOS simulator, use `localhost`. For physical devices, use your LAN IP.

---

## Firebase Setup

1. Create a Firebase project at https://console.firebase.google.com
2. Add Android app with package `tz.rishfy.app`, download `google-services.json` → `android/app/`
3. Add iOS app with bundle ID `tz.rishfy.app`, download `GoogleService-Info.plist` → `ios/Runner/`
4. Enable **Cloud Messaging**, **Analytics**, **Crashlytics**

For each environment, you can either use a separate Firebase project or switch at build time via flavors (recommended post-MVP).

---

## Google Maps Setup

1. Get an API key from https://console.cloud.google.com/apis/credentials
2. Enable: **Maps SDK for Android**, **Maps SDK for iOS**, **Places API**, **Distance Matrix API**, **Directions API**
3. Restrict the key to your app's package/bundle IDs
4. Paste the key into:
   - Android: `android/app/src/main/AndroidManifest.xml` — the `MAPS_API_KEY` placeholder
   - iOS: `ios/Runner/Info.plist` — the `GMSApiKey` entry
   - Flutter runtime: `assets/env/<env>.env` — the `GOOGLE_MAPS_API_KEY` entry

---

## Testing

```bash
flutter test                    # Unit + widget tests
flutter test integration_test/  # Integration tests on a device/emulator
flutter test --coverage         # With coverage report
```

Target: **80% coverage** on business logic (providers, repositories, controllers).
Minimum: **100% coverage** on error mapping and token refresh logic.

### Test structure

```
test/
├── unit/                  # Pure Dart logic — providers, repositories
├── widget/                # UI widget tests
└── fixtures/              # Shared test data
integration_test/          # Full app flows with a real backend
```

Use **mocktail** for mocks — it's null-safe and works without code generation.

---

## Building for Release

### Android

```bash
flutter build appbundle --release --dart-define=ENV=prod
# → build/app/outputs/bundle/release/app-release.aab
```

Before first release: configure signing in `android/key.properties` (see `android/key.properties.example`).

### iOS

```bash
flutter build ipa --release --dart-define=ENV=prod
# → build/ios/ipa/rishfy.ipa
```

Requires an Apple Developer account and Xcode for signing.

---

## LATRA Compliance Hooks

Specific mobile features required for LATRA compliance (see `docs/LATRA_COMPLIANCE.md`):

- **LATRA-OR-03** — Driver name + photo shown in `RouteDetailScreen` before booking
- **LATRA-OR-04** — Accurate pickup/destination coords via Google Places in `RouteSearchScreen`
- **LATRA-OR-08** — Emergency button in `ActiveTripScreen` AppBar
- **LATRA-OR-10** — Digital receipts shown in `BookingDetailScreen` after trip completion
- **LATRA-OR-11** — Push + SMS notifications on trip state changes (handled server-side, received via FCM)

---

## Code Style

Enforced via `analysis_options.yaml`. Key rules:

- `prefer_single_quotes`
- `prefer_const_constructors`
- `avoid_print` — always use `AppLogger`
- `unawaited_futures` — use `unawaited()` explicitly
- `sort_constructors_first`
- `directives_ordering`

Run `flutter analyze` before committing; CI will fail otherwise.

---

## Common Commands

```bash
# Regenerate code (after changing @riverpod, @freezed, @JsonSerializable annotations)
dart run build_runner watch --delete-conflicting-outputs

# Update all dependencies within constraints
flutter pub upgrade

# Check for outdated packages
flutter pub outdated

# Clean build cache (when weird errors happen)
flutter clean && flutter pub get

# Run on a specific device
flutter devices
flutter run -d <device-id>
```

---

## Troubleshooting

See [`docs/TROUBLESHOOTING.md`](../docs/TROUBLESHOOTING.md) for common issues. Mobile-specific gotchas:

- **"No connected devices"** — run `flutter doctor` and fix all checks
- **Android build fails with "SDK not found"** — set `ANDROID_HOME` env var
- **iOS build fails** — run `cd ios && pod install` after pulling new dependencies
- **HTTP calls fail on Android with "Cleartext not permitted"** — confirm `android:usesCleartextTraffic="true"` is set for dev builds (it is, in our `AndroidManifest.xml`)
- **Can't reach backend from emulator** — use `10.0.2.2` for Android, `localhost` for iOS simulator

---

## Ownership

While Fatma leads mobile, every team member contributes features for their backend services:

- **Stella** — auth/user screens, profile management
- **Godbless** — route search, post route, live trip map
- **Ezekiel** — booking flows, payment integration
- **Fatma** — notifications, emergency features, localization

Cross-cutting concerns (theme, network, router) are reviewed by all.
