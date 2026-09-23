import 'package:flutter/material.dart';
import '../main.dart';
import 'login_screen.dart';
import 'package:intl/intl.dart';
import 'account_history_screen.dart';
import 'add_transaction_screen.dart';
import 'customers_screen.dart';
import 'harvests_screen.dart';
import 'partners_screen.dart';
import 'report_screen.dart';
import 'staff_screen.dart';
import 'transaction_log_screen.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_ui.dart';

/// The current calendar month as a range, for deep-linking the "This
/// month" dashboard rows into Reports/Transactions pre-filtered to the
/// same period.
DateTimeRange _thisMonthRange() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0);
  return DateTimeRange(start: start, end: end);
}

Map<AppCurrency, double> _emptyTotals() => {
  for (final c in AppCurrency.values) c: 0.0,
};

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  bool _loading = true;
  String? _errorMessage;

  String? _name;
  String? _role;

  Map<AppCurrency, double> _cashOnHand = _emptyTotals();
  Map<AppCurrency, double> _outstandingLoans = _emptyTotals();
  Map<AppCurrency, double> _outstandingAdvances = _emptyTotals();
  Map<AppCurrency, double> _owedByCustomers = _emptyTotals();
  Map<AppCurrency, double> _monthCashOut = _emptyTotals();
  Map<AppCurrency, double> _monthBills = _emptyTotals();
  Map<AppCurrency, double> _monthPayroll = _emptyTotals();
  Map<AppCurrency, double> _monthAdvancesGiven = _emptyTotals();
  Map<AppCurrency, double> _monthRevenue = _emptyTotals();
  Map<AppCurrency, double> _monthHarvestValue = _emptyTotals();
  String? _pettyCashId;
  String? _revenueAccountId;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Called when a route pushed on top of the dashboard is popped and the
  // dashboard becomes visible again - covers every navigation path (FAB,
  // drawer links, back button), not just the ones that manually refresh.
  @override
  void didPopNext() {
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Profile (name + role)
      final profile = await supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      _name = profile['name'] as String?;
      _role = profile['role'] as String?;

      // 2. Opening balance (USD only - see settings table note in claude.md)
      final settingsRow = await supabase
          .from('settings')
          .select()
          .eq('key', 'opening_balance')
          .single();
      final opening = (settingsRow['value'] as num).toDouble();

      // 2b. Petty Cash's own ledger: transfers in/out to Investment/Loans/
      // Revenue, and currency exchanges (see Settings > Accounts).
      final pettyCashAccount = await supabase
          .from('accounts')
          .select()
          .eq('name', 'Petty Cash')
          .single();
      final pettyCashLedger = await supabase
          .from('account_transactions')
          .select('amount, currency, type')
          .eq('account_id', pettyCashAccount['id']);
      final pettyCashLedgerNet = _emptyTotals();
      for (final t in pettyCashLedger) {
        final currency = AppCurrency.fromCode(t['currency'] as String?);
        final amount = (t['amount'] as num).toDouble();
        if (t['type'] == 'transfer_in' || t['type'] == 'exchange_in') {
          pettyCashLedgerNet[currency] =
              (pettyCashLedgerNet[currency] ?? 0) + amount;
        } else if (t['type'] == 'transfer_out' || t['type'] == 'exchange_out') {
          pettyCashLedgerNet[currency] =
              (pettyCashLedgerNet[currency] ?? 0) - amount;
        }
      }

      // 3. All transactions (fine for small volume; we'll optimize later if needed)
      final txns = await supabase.from('transactions').select();

      // 4. Harvest sales + customer payments -> owed by customers, this
      // month's harvest sales value.
      final harvestSales = await supabase
          .from('harvest_sales')
          .select('kg_sold, price_per_kg, transport_fee, sale_date, currency');
      final customerPayments = await supabase
          .from('customer_payments')
          .select('amount, currency');

      // 5. Revenue account fund_add rows -> this month's revenue collected
      // (includes harvest sale payments; see customer_payments service).
      final revenueAccount = await supabase
          .from('accounts')
          .select()
          .eq('name', 'Revenue')
          .single();
      final revenueAdds = await supabase
          .from('account_transactions')
          .select('amount, transaction_date, currency')
          .eq('account_id', revenueAccount['id'])
          .eq('type', 'fund_add');

      final cash = _emptyTotals();
      cash[AppCurrency.usd] = (cash[AppCurrency.usd] ?? 0) + opening;
      for (final c in AppCurrency.values) {
        cash[c] = (cash[c] ?? 0) + (pettyCashLedgerNet[c] ?? 0);
      }
      final loansOut = _emptyTotals();
      final loansRepaid = _emptyTotals();
      final advancesOut = _emptyTotals();
      final advancesCleared = _emptyTotals();
      final monthCashOut = _emptyTotals();

      final now = DateTime.now();
      final monthBills = _emptyTotals();
      final monthPayroll = _emptyTotals();
      final monthAdvances = _emptyTotals();

      for (final t in txns) {
        final type = t['type'] as String;
        final currency = AppCurrency.fromCode(t['currency'] as String?);
        final amount = (t['amount'] as num).toDouble();
        final date = DateTime.parse(t['transaction_date'] as String);
        final isThisMonth = date.year == now.year && date.month == now.month;

        switch (type) {
          case 'expense':
            cash[currency] = (cash[currency] ?? 0) - amount;
            if (isThisMonth) {
              monthBills[currency] = (monthBills[currency] ?? 0) + amount;
              monthCashOut[currency] = (monthCashOut[currency] ?? 0) + amount;
            }
            break;
          case 'payroll':
            cash[currency] = (cash[currency] ?? 0) - amount;
            if (isThisMonth) {
              monthPayroll[currency] = (monthPayroll[currency] ?? 0) + amount;
              monthCashOut[currency] = (monthCashOut[currency] ?? 0) + amount;
            }
            break;
          case 'loan':
            cash[currency] = (cash[currency] ?? 0) - amount;
            loansOut[currency] = (loansOut[currency] ?? 0) + amount;
            if (isThisMonth) {
              monthCashOut[currency] = (monthCashOut[currency] ?? 0) + amount;
            }
            break;
          case 'advance':
            cash[currency] = (cash[currency] ?? 0) - amount;
            advancesOut[currency] = (advancesOut[currency] ?? 0) + amount;
            if (isThisMonth) {
              monthAdvances[currency] = (monthAdvances[currency] ?? 0) + amount;
              monthCashOut[currency] = (monthCashOut[currency] ?? 0) + amount;
            }
            break;
          case 'loan_repayment':
            cash[currency] = (cash[currency] ?? 0) + amount;
            loansRepaid[currency] = (loansRepaid[currency] ?? 0) + amount;
            break;
          case 'advance_deduction':
            advancesCleared[currency] =
                (advancesCleared[currency] ?? 0) + amount; // no cash impact
            break;
        }
      }

      final harvestTotalValue = _emptyTotals();
      final monthHarvestValue = _emptyTotals();
      for (final h in harvestSales) {
        final currency = AppCurrency.fromCode(h['currency'] as String?);
        final transportFee = (h['transport_fee'] as num? ?? 0).toDouble();
        final value =
            (h['kg_sold'] as num).toDouble() *
                (h['price_per_kg'] as num).toDouble() -
            transportFee;
        harvestTotalValue[currency] =
            (harvestTotalValue[currency] ?? 0) + value;
        final date = DateTime.parse(h['sale_date'] as String);
        if (date.year == now.year && date.month == now.month) {
          monthHarvestValue[currency] =
              (monthHarvestValue[currency] ?? 0) + value;
        }
      }
      final totalPaidByCustomers = _emptyTotals();
      for (final p in customerPayments) {
        final currency = AppCurrency.fromCode(p['currency'] as String?);
        totalPaidByCustomers[currency] =
            (totalPaidByCustomers[currency] ?? 0) +
            (p['amount'] as num).toDouble();
      }

      final monthRevenue = _emptyTotals();
      for (final r in revenueAdds) {
        final date = DateTime.parse(r['transaction_date'] as String);
        if (date.year == now.year && date.month == now.month) {
          final currency = AppCurrency.fromCode(r['currency'] as String?);
          monthRevenue[currency] =
              (monthRevenue[currency] ?? 0) + (r['amount'] as num).toDouble();
        }
      }

      if (!mounted) return;
      setState(() {
        _cashOnHand = cash;
        _outstandingLoans = {
          for (final c in AppCurrency.values)
            c: (loansOut[c] ?? 0) - (loansRepaid[c] ?? 0),
        };
        _outstandingAdvances = {
          for (final c in AppCurrency.values)
            c: (advancesOut[c] ?? 0) - (advancesCleared[c] ?? 0),
        };
        _owedByCustomers = {
          for (final c in AppCurrency.values)
            c: (harvestTotalValue[c] ?? 0) - (totalPaidByCustomers[c] ?? 0),
        };
        _monthCashOut = monthCashOut;
        _monthBills = monthBills;
        _monthPayroll = monthPayroll;
        _monthAdvancesGiven = monthAdvances;
        _monthRevenue = monthRevenue;
        _monthHarvestValue = monthHarvestValue;
        _pettyCashId = pettyCashAccount['id'] as String;
        _revenueAccountId = revenueAccount['id'] as String;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading dashboard: $e';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 21),
            color: AppColors.inkSecondary,
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: AppDrawer(name: _name, role: _role),
      floatingActionButton: _role == 'admin'
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
              ),
              icon: const Icon(Icons.add, size: 22),
              label: const Text(
                'New',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_errorMessage!)),
            )
          : RefreshIndicator(
              onRefresh: _loadEverything,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                children: [
                  _greeting(),
                  const SizedBox(height: 16),
                  _cashHeroCard(),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.handshake_outlined,
                          label: 'Owed by partners',
                          valueWidget: DualCurrencyStat(
                            amounts: _outstandingLoans,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          color: AppColors.loan,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PartnersScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          icon: Icons.person_outline,
                          label: 'Owed by staff',
                          valueWidget: DualCurrencyStat(
                            amounts: _outstandingAdvances,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          color: AppColors.advance,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const StaffScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.groups_outlined,
                          label: 'Owed by customers',
                          valueWidget: DualCurrencyStat(
                            amounts: _owedByCustomers,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          color: AppColors.brandGreenLight,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CustomersScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          icon: Icons.calendar_month_outlined,
                          label: 'This month\'s cash out',
                          valueWidget: DualCurrencyStat(
                            amounts: _monthCashOut,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          color: AppColors.brandNavy,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TransactionLogScreen(
                                initialDateRange: _thisMonthRange(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SectionLabel(
                    'THIS MONTH',
                    trailing: Text(
                      DateFormat('MMMM yyyy').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        _monthRow(
                          Icons.receipt_long_outlined,
                          'Expenses',
                          _monthBills,
                          AppColors.expense,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReportScreen(
                                initialAccount: 'Expenses',
                                initialDateRange: _thisMonthRange(),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        _monthRow(
                          Icons.payments_outlined,
                          'Payroll',
                          _monthPayroll,
                          AppColors.payroll,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReportScreen(
                                initialAccount: 'Payroll',
                                initialDateRange: _thisMonthRange(),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        _monthRow(
                          Icons.back_hand_outlined,
                          'Advances',
                          _monthAdvancesGiven,
                          AppColors.advance,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReportScreen(
                                initialAccount: 'Advances',
                                initialDateRange: _thisMonthRange(),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        _monthRow(
                          Icons.attach_money,
                          'Revenue',
                          _monthRevenue,
                          AppColors.cashIn,
                          onTap: _revenueAccountId == null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AccountHistoryScreen(
                                      accountId: _revenueAccountId!,
                                      accountName: 'Revenue',
                                    ),
                                  ),
                                ),
                        ),
                        const Divider(height: 1),
                        _monthRow(
                          Icons.eco_outlined,
                          'Harvest sales',
                          _monthHarvestValue,
                          AppColors.brandGreenLight,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HarvestsScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  AppCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TransactionLogScreen(),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const IconBadge(
                          icon: Icons.list_alt_outlined,
                          color: AppColors.brandGreenLight,
                          size: 34,
                          iconSize: 17,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'View all transactions',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppColors.inkMuted.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _greeting() {
    final isAdmin = _role == 'admin';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 2),
              Text(
                _name ?? '',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        if (_role != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: (isAdmin ? AppColors.brandGreen : AppColors.brandNavy)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppStyles.radiusPill),
            ),
            child: Text(
              isAdmin ? 'Admin' : 'Viewer',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: isAdmin ? AppColors.brandGreen : AppColors.brandNavy,
              ),
            ),
          ),
      ],
    );
  }

  Widget _cashHeroCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreen.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pettyCashId == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AccountHistoryScreen(
                        accountId: _pettyCashId!,
                        accountName: 'Petty Cash',
                      ),
                    ),
                  ),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandGreenLight, AppColors.brandGreenDeep],
                ),
              ),
              child: Stack(
                children: [
                  // Soft decorative rings, clipped by the card's rounded corners.
                  Positioned(
                    top: -46,
                    right: -28,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -62,
                    right: 40,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 17,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Cash on hand',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: DualCurrencyStat(
                            amounts: _cashOnHand,
                            spacing: 4,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthRow(
    IconData icon,
    String label,
    Map<AppCurrency, double> amounts,
    Color color, {
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 32, iconSize: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          DualCurrencyStat(
            amounts: amounts,
            crossAxisAlignment: CrossAxisAlignment.end,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkMuted),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
