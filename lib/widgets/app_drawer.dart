import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/login_screen.dart';
import '../screens/transaction_log_screen.dart';
import '../screens/report_screen.dart';
import '../screens/expense_categories_screen.dart';
import '../screens/staff_screen.dart';
import '../screens/partners_screen.dart';
import '../screens/settings_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.name, required this.role});

  final String? name;
  final String? role;

  void _go(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout(BuildContext context) async {
    Navigator.of(context).pop();
    await supabase.auth.signOut();
    if (context.mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';

    return Drawer(
      backgroundColor: const Color(0xFFF7F7F5),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/images/logo_main.jpeg', width: 160),
                  if (name != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      name!,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Transactions'),
              onTap: () => _go(context, const TransactionLogScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Reports'),
              onTap: () => _go(context, const ReportScreen()),
            ),
            if (isAdmin) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'MANAGE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Expense categories'),
                onTap: () => _go(context, const ExpenseCategoriesScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Staff'),
                onTap: () => _go(context, const StaffScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.handshake_outlined),
                title: const Text('Partners'),
                onTap: () => _go(context, const PartnersScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () => _go(context, const SettingsScreen()),
              ),
            ],
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () => _logout(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
