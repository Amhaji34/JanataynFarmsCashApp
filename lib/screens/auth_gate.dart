import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/push_notifications.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

// Sign-out itself unregisters this device's token (see
// app_drawer.dart's _logout, which does so before calling
// supabase.auth.signOut()) - by the time a signedOut event reaches here,
// the session is already gone and can no longer authorize the delete.

/// Routes straight to the dashboard when a session is already cached
/// locally (supabase_flutter persists it and auto-refreshes the token),
/// so signing in once keeps you signed in across app restarts instead of
/// always landing back on the login screen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    if (supabase.auth.currentSession != null) setUpPushNotifications();
    supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) setUpPushNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? supabase.auth.currentSession;
        return session != null ? const DashboardScreen() : const LoginScreen();
      },
    );
  }
}
