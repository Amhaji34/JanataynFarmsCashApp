import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart';

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
Future<void> setUpPushNotifications() async {
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);
  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
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
    );
  });

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
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await supabase.from('device_tokens').delete().eq('token', token);
  } catch (e) {
    debugPrint('Could not unregister device token: $e');
  }
}
