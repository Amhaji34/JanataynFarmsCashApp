import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/login_screen.dart';
import '../screens/transaction_log_screen.dart';
import '../screens/report_screen.dart';
import '../screens/payroll_screen.dart';
import '../screens/harvests_screen.dart';
import '../screens/customers_screen.dart';
import '../screens/expense_categories_screen.dart';
import '../screens/staff_screen.dart';
import '../screens/partners_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/suppliers_screen.dart';
import '../theme/app_theme.dart';
import 'app_ui.dart';

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

  Widget _navTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Widget destination,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _go(context, destination),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                IconBadge(icon: icon, color: color, size: 34, iconSize: 17),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';

    return Drawer(
      backgroundColor: AppColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandGreenLight, AppColors.brandGreenDeep],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandLogo(width: 168, padding: 9),
                    if (name != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        name!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isAdmin ? 'Administrator' : 'Viewer',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              children: [
                // Group 1: Accounts, Harvests, Run Payroll, Transactions,
                // Reports.
                if (isAdmin)
                  _navTile(
                    context: context,
                    icon: Icons.account_balance_outlined,
                    label: 'Accounts',
                    color: AppColors.neutral,
                    destination: const SettingsScreen(),
                  ),
                _navTile(
                  context: context,
                  icon: Icons.eco_outlined,
                  label: 'Harvests',
                  color: AppColors.brandGreenLight,
                  destination: const HarvestsScreen(),
                ),
                if (isAdmin)
                  _navTile(
                    context: context,
                    icon: Icons.payments_outlined,
                    label: 'Run Payroll',
                    color: AppColors.payroll,
                    destination: const PayrollScreen(),
                  ),
                _navTile(
                  context: context,
                  icon: Icons.receipt_long_outlined,
                  label: 'Transactions',
                  color: AppColors.expense,
                  destination: const TransactionLogScreen(),
                ),
                _navTile(
                  context: context,
                  icon: Icons.bar_chart_rounded,
                  label: 'Reports',
                  color: AppColors.loan,
                  destination: const ReportScreen(),
                ),

                // Group 2: Expense categories, Customers, Staff, Partners.
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, indent: 20, endIndent: 20),
                ),
                if (isAdmin)
                  _navTile(
                    context: context,
                    icon: Icons.category_outlined,
                    label: 'Expense categories',
                    color: AppColors.payroll,
                    destination: const ExpenseCategoriesScreen(),
                  ),
                _navTile(
                  context: context,
                  icon: Icons.groups_outlined,
                  label: 'Customers',
                  color: AppColors.brandNavy,
                  destination: const CustomersScreen(),
                ),
                _navTile(
                  context: context,
                  icon: Icons.local_shipping_outlined,
                  label: 'Suppliers',
                  color: AppColors.expense,
                  destination: const SuppliersScreen(),
                ),
                if (isAdmin) ...[
                  _navTile(
                    context: context,
                    icon: Icons.people_outline,
                    label: 'Staff',
                    color: AppColors.advance,
                    destination: const StaffScreen(),
                  ),
                  _navTile(
                    context: context,
                    icon: Icons.handshake_outlined,
                    label: 'Partners',
                    color: AppColors.brandNavy,
                    destination: const PartnersScreen(),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _logout(context),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout,
                          size: 19,
                          color: AppColors.inkSecondary,
                        ),
                        SizedBox(width: 14),
                        Text(
                          'Log out',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
