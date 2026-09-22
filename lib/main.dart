import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_gate.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Janatayn Farms Cash Manager',
      debugShowCheckedModeBanner: false,
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
