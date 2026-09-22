import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'account_history_screen.dart';
import 'add_funds_screen.dart';
import 'exchange_screen.dart';
import 'transfer_funds_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _accountOrder = ['Investment', 'Loans', 'Revenue', 'Petty Cash'];
  static const _accountIcons = {
    'Investment': Icons.trending_up,
    'Loans': Icons.account_balance_outlined,
    'Revenue': Icons.attach_money,
    'Petty Cash': Icons.account_balance_wallet_outlined,
  };

  bool _accountsLoading = true;
  String? _accountsError;
  List<Map<String, dynamic>> _accounts = [];
  Map<String, Map<AppCurrency, double>> _accountBalances = {};

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _accountsLoading = true);
    try {
      final accountsData = await supabase.from('accounts').select();
      final accounts = List<Map<String, dynamic>>.from(accountsData)
        ..sort(
          (a, b) => _accountOrder
              .indexOf(a['name'] as String)
              .compareTo(_accountOrder.indexOf(b['name'] as String)),
        );

      final ledgerData = await supabase.from('account_transactions').select();
      final ledger = List<Map<String, dynamic>>.from(ledgerData);

      final settingsRow = await supabase
          .from('settings')
          .select()
          .eq('key', 'opening_balance')
          .single();
      final opening = (settingsRow['value'] as num).toDouble();

      final txnsData = await supabase.from('transactions').select();
      final txns = List<Map<String, dynamic>>.from(txnsData);

      final balances = <String, Map<AppCurrency, double>>{};
      for (final account in accounts) {
        final id = account['id'] as String;
        final name = account['name'] as String;
        final balance = {for (final c in AppCurrency.values) c: 0.0};

        for (final t in ledger) {
          if (t['account_id'] != id) continue;
          final currency = AppCurrency.fromCode(t['currency'] as String?);
          final amount = (t['amount'] as num).toDouble();
          if (t['type'] == 'fund_add' ||
              t['type'] == 'transfer_in' ||
              t['type'] == 'exchange_in') {
            balance[currency] = (balance[currency] ?? 0) + amount;
          } else if (t['type'] == 'transfer_out' ||
              t['type'] == 'exchange_out') {
            balance[currency] = (balance[currency] ?? 0) - amount;
          }
        }

        if (name == 'Petty Cash') {
          balance[AppCurrency.usd] = (balance[AppCurrency.usd] ?? 0) + opening;
          for (final t in txns) {
            final currency = AppCurrency.fromCode(t['currency'] as String?);
            final amount = (t['amount'] as num).toDouble();
            switch (t['type']) {
              case 'expense':
              case 'payroll':
              case 'loan':
              case 'advance':
                balance[currency] = (balance[currency] ?? 0) - amount;
                break;
              case 'loan_repayment':
                balance[currency] = (balance[currency] ?? 0) + amount;
                break;
            }
          }
        }

        balances[id] = balance;
      }

      setState(() {
        _accounts = accounts;
        _accountBalances = balances;
        _accountsLoading = false;
      });
    } catch (e) {
      setState(() {
        _accountsError = 'Could not load accounts: $e';
        _accountsLoading = false;
      });
    }
  }

  Future<void> _openAddFunds() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddFundsScreen()));
    if (result == true) _loadAccounts();
  }

  Future<void> _openTransferFunds() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TransferFundsScreen()),
    );
    if (result == true) _loadAccounts();
  }

  Future<void> _openExchange() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ExchangeScreen()));
    if (result == true) _loadAccounts();
  }

  Future<void> _openAccountHistory(Map<String, dynamic> account) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountHistoryScreen(
          accountId: account['id'] as String,
          accountName: account['name'] as String,
        ),
      ),
    );
    _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: _accountsLoading
          ? const Center(child: CircularProgressIndicator())
          : _accountsError != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_accountsError!)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(AppStyles.radiusCard),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppColors.brandNavy.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cash on hand is the Petty Cash account: funded '
                          'only by transfers in from Investment, Loans or '
                          'Revenue, minus expenses, payroll, loans and '
                          'advances (plus loan repayments).',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: AppColors.brandNavy.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                SectionLabel(
                  'ACCOUNTS',
                  trailing: TextButton.icon(
                    onPressed: _openTransferFunds,
                    icon: const Icon(Icons.sync_alt, size: 16),
                    label: const Text('Transfer'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: _accounts.map((account) {
                    final name = account['name'] as String;
                    final color = AppColors.accentFor(name);
                    final balance = _accountBalances[account['id']] ?? {};
                    return AppCard(
                      accent: color,
                      padding: const EdgeInsets.all(14),
                      onTap: () => _openAccountHistory(account),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconBadge(
                            icon:
                                _accountIcons[name] ??
                                Icons.account_balance_outlined,
                            color: color,
                            size: 32,
                            iconSize: 16,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          DualCurrencyStat(
                            amounts: balance,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _openAddFunds,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add funds'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _openExchange,
                          icon: const Icon(Icons.currency_exchange, size: 18),
                          label: const Text('Exchange'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
