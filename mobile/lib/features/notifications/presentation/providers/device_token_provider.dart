import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/dio_client.dart';
import '../../data/datasources/device_remote_datasource.dart';

const String _kDeviceIdKey = 'rishfy_device_id';

final Provider<DeviceRemoteDataSource> _deviceDataSourceProvider =
    Provider<DeviceRemoteDataSource>(
  (Ref ref) => DeviceRemoteDataSource(ref.read(dioClientProvider)),
);

/// Call once after successful auth (login or OTP verify).
/// Safe to call multiple times — idempotent.
final FutureProvider<void> registerDeviceTokenProvider =
    FutureProvider<void>((Ref ref) async {
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  final NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  if (settings.authorizationStatus == AuthorizationStatus.denied) return;

  final String? token = await messaging.getToken();
  if (token == null) return;

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  String? deviceId = prefs.getString(_kDeviceIdKey);
  if (deviceId == null) {
    deviceId = const Uuid().v4();
    await prefs.setString(_kDeviceIdKey, deviceId);
  }

  final String platform = Platform.isIOS ? 'ios' : 'android';
  final DeviceRemoteDataSource ds = ref.read(_deviceDataSourceProvider);

  try {
    await ds.registerToken(
      deviceId: deviceId,
      fcmToken: token,
      platform: platform,
    );
  } catch (_) {}

  // Re-register whenever the FCM token rotates.
  messaging.onTokenRefresh.listen((String newToken) async {
    try {
      await ds.refreshToken(deviceId: deviceId!, fcmToken: newToken);
    } catch (_) {}
  });
});
