import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/login_screen.dart';
import '../services/push_notifications.dart';
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
    await unregisterPushToken();
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
                    style: TextStyle(
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
            decoration: BoxDecoration(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: _ThemeModeToggle(),
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
                  child: Padding(
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

/// Three-way Light/Dark/System pill, mirroring CurrencyToggle's segmented
/// style (lib/utils/currency.dart). Defaults to System until the user
/// picks a side; the choice is persisted by AppThemeController.
class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle();

  static const _options = [
    (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
    (ThemeMode.system, Icons.brightness_auto_outlined, 'System'),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final current = AppThemeController.instance.mode;
        return Row(
          children: [
            for (final (mode, icon, label) in _options) ...[
              if (mode != _options.first.$1) const SizedBox(width: 8),
              Expanded(child: _segment(mode, icon, label, current)),
            ],
          ],
        );
      },
    );
  }

  Widget _segment(
    ThemeMode mode,
    IconData icon,
    String label,
    ThemeMode current,
  ) {
    final selected = mode == current;
    return Material(
      color: selected
          ? AppColors.brandGreen.withValues(alpha: 0.10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusField),
      child: InkWell(
        onTap: () => AppThemeController.instance.setMode(mode),
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
            border: Border.all(
              color: selected
                  ? AppColors.brandGreen.withValues(alpha: 0.45)
                  : AppColors.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? AppColors.brandGreen : AppColors.inkMuted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppColors.brandGreen
                      : AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
