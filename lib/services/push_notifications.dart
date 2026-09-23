import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart';
import '../screens/notification_detail_screen.dart';

/// The channel every transaction push notification is sent on - must
/// match AndroidManifest.xml's `default_notification_channel_id` and the
/// channel the sending Edge Function targets.
const _channel = AndroidNotificationChannel(
  'transactions',
  'Transactions',
  description: 'A notification for every new transaction recorded.',
  importance: Importance.high,
);

final _localNotifications = FlutterLocalNotificationsPlugin();

Map<String, String> _stringData(Map<String, dynamic> data) =>
    data.map((key, value) => MapEntry(key, value?.toString() ?? ''));

/// Opens NotificationDetailScreen for a tapped notification's payload -
/// shared by all three tap paths below (foreground/local notification,
/// background tap, and cold-start launch).
void _openNotificationDetail(Map<String, String> data) {
  if (data['title'] == null) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => NotificationDetailScreen(data: data)),
  );
}

/// Must be a top-level (or static) function - the platform calls this in
/// its own background isolate when a push arrives while the app isn't in
/// the foreground.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing to do here: a `notification` payload is already shown by the
  // OS automatically when the app is backgrounded/terminated. This
  // handler just needs to exist so FCM knows the app supports background
  // delivery.
}

/// Sets up local notification display for foreground pushes (Android
/// doesn't auto-show a `notification` payload while the app is in the
/// foreground - only when backgrounded/terminated) and registers this
/// device's FCM token in `device_tokens` so the push-notification Edge
/// Function knows where to send. Call once after login.
///
/// No-ops on web/desktop - this app only ships on Android, and
/// firebase_options.dart has no config for other platforms. A
/// transaction added from a non-Android build still triggers pushes to
/// every registered Android device (the Postgres trigger sends them,
/// not the client), so this just means that build never registers
/// itself as a push target.
Future<void> setUpPushNotifications() async {
  if (kIsWeb) return;
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);
  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    // Tapped the local notification shown below while the app was
    // already in the foreground.
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload == null) return;
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      _openNotificationDetail(_stringData(decoded));
    },
  );

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  FirebaseMessaging.onMessage.listen((message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(_stringData(message.data)),
    );
  });

  // Tapped the OS-shown notification while the app was backgrounded
  // (not foreground, not terminated).
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _openNotificationDetail(_stringData(message.data));
  });

  // App was launched (cold start) by tapping a notification - handled
  // once here rather than relying on onMessageOpenedApp, which only
  // fires for a background→foreground transition, not a fresh launch.
  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    final data = _stringData(initialMessage.data);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openNotificationDetail(data),
    );
  }

  await _registerToken();
  messaging.onTokenRefresh.listen((_) => _registerToken());
}

Future<void> _registerToken() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    final userId = supabase.auth.currentUser?.id;
    if (token == null || userId == null) return;

    await supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'token');
  } catch (e) {
    // Best-effort: a failure here shouldn't block login or app usage,
    // it just means this device won't get pushes until the next retry
    // (e.g. next login, or the next token refresh).
    debugPrint('Could not register device token: $e');
  }
}

/// Removes this device's token on logout, so a signed-out device stops
/// receiving pushes meant for whoever's account it was registered under.
Future<void> unregisterPushToken() async {
  if (kIsWeb) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await supabase.from('device_tokens').delete().eq('token', token);
  } catch (e) {
    debugPrint('Could not unregister device token: $e');
  }
}
