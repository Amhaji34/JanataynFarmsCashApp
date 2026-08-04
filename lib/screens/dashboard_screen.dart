import 'package:flutter/material.dart';
import '../main.dart';
import 'login_screen.dart';
import 'package:intl/intl.dart';
import 'add_transaction_screen.dart';
import 'transaction_log_screen.dart';
import '../widgets/app_drawer.dart';

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

      // 3. All transactions (fine for small volume; we'll optimize later if needed)
      final txns = await supabase.from('transactions').select();

      double cash = opening;
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
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: const Color(0xFFF7F7F5),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      drawer: AppDrawer(name: _name, role: _role),
      floatingActionButton: _role == 'admin'
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddTransactionScreen(),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Welcome back',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  _name ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),

                // Cash on hand card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cash on hand',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatCurrency(_cashOnHand),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Two metric cards side by side
                Row(
                  children: [
                    Expanded(
                      child: _metricCard(
                        icon: Icons.people_outline,
                        label: 'Owed by partners',
                        value: _outstandingLoans,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metricCard(
                        icon: Icons.person_outline,
                        label: 'Owed by staff',
                        value: _outstandingAdvances,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Expense summary cards side by side
                Row(
                  children: [
                    Expanded(
                      child: _metricCard(
                        icon: Icons.trending_down_outlined,
                        label: 'Total expenses',
                        value: _totalExpenses,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metricCard(
                        icon: Icons.calendar_month_outlined,
                        label: 'This month\'s expenses',
                        value: _monthExpenses,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Text(
                  'This month',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),

                const SizedBox(height: 10),
                _monthRow(Icons.receipt_long_outlined, 'Expenses', _monthBills),
                _monthRow(Icons.payments_outlined, 'Payroll', _monthPayroll),
                _monthRow(
                  Icons.back_hand_outlined,
                  'Advances',
                  _monthAdvancesGiven,
                ),
                const SizedBox(height: 10),
                Center(
                  child: Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TransactionLogScreen(),
                        ),
                      ),
                      child: const Text('View all transactions'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required double value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(
            _formatCurrency(value),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _monthRow(IconData icon, String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
          Text(
            _formatCurrency(value),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
