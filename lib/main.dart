import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/push_notifications.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // This app only ships on Android - push notifications aren't wired up
  // for web (see firebase_options.dart) or desktop. A transaction added
  // from the web build still triggers pushes to registered Android
  // devices (the Postgres trigger sends them, not the client), so
  // skipping Firebase here doesn't affect that - it just means the web
  // build itself never registers as a push target.
  if (!kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await Supabase.initialize(
    url: 'https://jgxqvhryinoulpztprwz.supabase.co',
    publishableKey: 'sb_publishable_mZxZOdYrNt9fBmuA9V7w2Q_yxDxiPrJ',
    // Keeps the session alive across app restarts: the refresh token is
    // persisted locally and used silently, so once logged in, a partner
    // stays logged in instead of landing back on the login screen.
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  runApp(const MyApp());
}

// Handy shortcut you'll use everywhere later
final supabase = Supabase.instance.client;

// Lets screens (e.g. the dashboard) detect when they've become visible
// again after a pushed route is popped, so they can refresh their data.
final routeObserver = RouteObserver<PageRoute>();

// Lets services/push_notifications.dart push a route (e.g. the tapped
// notification's detail screen) without needing a BuildContext of its
// own - notification taps can arrive before any screen has one ready
// (cold start) or from a background isolate.
final navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Janatayn Farms Cash Manager',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}
