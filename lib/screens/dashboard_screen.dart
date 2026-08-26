import 'package:flutter/material.dart';
import '../main.dart';
import 'login_screen.dart';
import 'package:intl/intl.dart';
import 'add_transaction_screen.dart';
import 'transaction_log_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_ui.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

String _formatCurrency(double value) {
  final formatter = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  return formatter.format(value);
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  bool _loading = true;
  String? _errorMessage;

  String? _name;
  String? _role;

  double _cashOnHand = 0;
  double _outstandingLoans = 0;
  double _outstandingAdvances = 0;
  double _totalExpenses = 0;
  double _monthExpenses = 0;
  double _monthBills = 0;
  double _monthPayroll = 0;
  double _monthAdvancesGiven = 0;

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

      // 2. Opening balance
      final settingsRow = await supabase
          .from('settings')
          .select()
          .eq('key', 'opening_balance')
          .single();
      final opening = (settingsRow['value'] as num).toDouble();

      // 2b. Petty Cash top-ups (transfers in from Investment/Loans/Revenue -
      // the only way Petty Cash is ever funded; see Settings > Accounts).
      final pettyCashAccount = await supabase
          .from('accounts')
          .select()
          .eq('name', 'Petty Cash')
          .single();
      final transfersIn = await supabase
          .from('account_transactions')
          .select('amount')
          .eq('account_id', pettyCashAccount['id'])
          .eq('type', 'transfer_in');
      double pettyCashTransfersIn = 0;
      for (final t in transfersIn) {
        pettyCashTransfersIn += (t['amount'] as num).toDouble();
      }

      // 3. All transactions (fine for small volume; we'll optimize later if needed)
      final txns = await supabase.from('transactions').select();

      double cash = opening + pettyCashTransfersIn;
      double loansOut = 0;
      double loansRepaid = 0;
      double advancesOut = 0;
      double advancesCleared = 0;
      double totalExpenses = 0;
      double monthExpenses = 0;

      final now = DateTime.now();
      double monthBills = 0;
      double monthPayroll = 0;
      double monthAdvances = 0;

      for (final t in txns) {
        final type = t['type'] as String;
        final amount = (t['amount'] as num).toDouble();
        final date = DateTime.parse(t['transaction_date'] as String);
        final isThisMonth = date.year == now.year && date.month == now.month;

        switch (type) {
          case 'expense':
            cash -= amount;
            totalExpenses += amount;
            if (isThisMonth) {
              monthBills += amount;
              monthExpenses += amount;
            }
            break;
          case 'payroll':
            cash -= amount;
            totalExpenses += amount;
            if (isThisMonth) {
              monthPayroll += amount;
              monthExpenses += amount;
            }
            break;
          case 'loan':
            cash -= amount;
            loansOut += amount;
            break;
          case 'advance':
            cash -= amount;
            advancesOut += amount;
            if (isThisMonth) monthAdvances += amount;
            break;
          case 'loan_repayment':
            cash += amount;
            loansRepaid += amount;
            break;
          case 'advance_deduction':
            advancesCleared += amount; // no cash impact
            break;
        }
      }

      if (!mounted) return;
      setState(() {
        _cashOnHand = cash;
        _outstandingLoans = loansOut - loansRepaid;
        _outstandingAdvances = advancesOut - advancesCleared;
        _totalExpenses = totalExpenses;
        _monthExpenses = monthExpenses;
        _monthBills = monthBills;
        _monthPayroll = monthPayroll;
        _monthAdvancesGiven = monthAdvances;
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
                MaterialPageRoute(
                  builder: (_) => const AddTransactionScreen(),
                ),
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
          : ListView(
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
                        value: _formatCurrency(_outstandingLoans),
                        color: AppColors.loan,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: Icons.person_outline,
                        label: 'Owed by staff',
                        value: _formatCurrency(_outstandingAdvances),
                        color: AppColors.advance,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.trending_down_outlined,
                        label: 'Total expenses',
                        value: _formatCurrency(_totalExpenses),
                        color: AppColors.expense,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatTile(
                        icon: Icons.calendar_month_outlined,
                        label: 'This month\'s expenses',
                        value: _formatCurrency(_monthExpenses),
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SectionLabel(
                  'THIS MONTH',
                  trailing: Text(
                    DateFormat('MMMM yyyy').format(DateTime.now()),
                    style: const TextStyle(
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
                      ),
                      const Divider(height: 1),
                      _monthRow(
                        Icons.payments_outlined,
                        'Payroll',
                        _monthPayroll,
                        AppColors.payroll,
                      ),
                      const Divider(height: 1),
                      _monthRow(
                        Icons.back_hand_outlined,
                        'Advances',
                        _monthAdvancesGiven,
                        AppColors.advance,
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
                      const Expanded(
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
              const Text(
                'Welcome back',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 2),
              Text(
                _name ?? '',
                style: const TextStyle(
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
                      child: Text(
                        _formatCurrency(_cashOnHand),
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
    );
  }

  Widget _monthRow(IconData icon, String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 32, iconSize: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            _formatCurrency(value),
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
