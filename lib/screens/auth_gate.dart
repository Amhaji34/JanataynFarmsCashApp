import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Routes straight to the dashboard when a session is already cached
/// locally (supabase_flutter persists it and auto-refreshes the token),
/// so signing in once keeps you signed in across app restarts instead of
/// always landing back on the login screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
