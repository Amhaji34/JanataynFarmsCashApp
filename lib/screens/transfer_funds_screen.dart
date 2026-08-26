import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Transfers funds from one of Investment/Loans/Revenue into Petty Cash —
/// the only path by which Petty Cash ever gets funded. Records two ledger
/// rows: a transfer_out on the source account and a transfer_in on Petty
/// Cash, so each account's history reads correctly on its own.
class TransferFundsScreen extends StatefulWidget {
  const TransferFundsScreen({super.key});

  @override
  State<TransferFundsScreen> createState() => _TransferFundsScreenState();
}

class _TransferFundsScreenState extends State<TransferFundsScreen> {
  static const _sourceAccounts = ['Investment', 'Loans', 'Revenue'];

  bool _loadingAccounts = true;
  String? _loadError;
  List<Map<String, dynamic>> _accounts = [];
  Map<String, double> _balances = {};
  String? _pettyCashId;
  String? _selectedAccountId;

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');
  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() => _loadingAccounts = true);
    try {
      final accountsData = await supabase.from('accounts').select();
      final allAccounts = List<Map<String, dynamic>>.from(accountsData);
      final pettyCash = allAccounts.firstWhere(
        (a) => a['name'] == 'Petty Cash',
      );

      final ledgerData = await supabase.from('account_transactions').select();
      final ledger = List<Map<String, dynamic>>.from(ledgerData);

      final sources = allAccounts
          .where((a) => _sourceAccounts.contains(a['name']))
          .toList()
        ..sort(
          (a, b) => _sourceAccounts
              .indexOf(a['name'] as String)
              .compareTo(_sourceAccounts.indexOf(b['name'] as String)),
        );

      final balances = <String, double>{};
      for (final account in sources) {
        final id = account['id'] as String;
        double balance = 0;
        for (final t in ledger) {
          if (t['account_id'] != id) continue;
          final amount = (t['amount'] as num).toDouble();
          if (t['type'] == 'fund_add' || t['type'] == 'transfer_in') {
            balance += amount;
          } else if (t['type'] == 'transfer_out') {
            balance -= amount;
          }
        }
        balances[id] = balance;
      }

      setState(() {
        _accounts = sources;
        _balances = balances;
        _pettyCashId = pettyCash['id'] as String;
        _loadingAccounts = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Could not load accounts: $e';
        _loadingAccounts = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    setState(() => _errorMessage = null);

    if (_selectedAccountId == null) {
      setState(() => _errorMessage = 'Select an account to transfer from.');
      return;
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      setState(() => _errorMessage = 'Enter an amount greater than zero.');
      return;
    }
    final available = _balances[_selectedAccountId] ?? 0;
    if (amount > available + 0.01) {
      setState(
        () => _errorMessage =
            'Only ${_currency.format(available)} available in this account.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final date = _dbDateFormat.format(_selectedDate);
      final note = _noteController.text.trim();

      await supabase.from('account_transactions').insert([
        {
          'account_id': _selectedAccountId,
          'type': 'transfer_out',
          'amount': amount,
          'related_account_id': _pettyCashId,
          'transaction_date': date,
          'note': note,
        },
        {
          'account_id': _pettyCashId,
          'type': 'transfer_in',
          'amount': amount,
          'related_account_id': _selectedAccountId,
          'transaction_date': date,
          'note': note,
        },
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer to Petty Cash')),
      body: _loadingAccounts
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_loadError!)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const SectionLabel('TRANSFER FROM'),
                const SizedBox(height: 8),
                ..._accounts.map((a) {
                  final id = a['id'] as String;
                  final name = a['name'] as String;
                  final selected = id == _selectedAccountId;
                  final color = AppColors.accentFor(name);
                  final balance = _balances[id] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      accent: selected ? color : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () => setState(() => _selectedAccountId = id),
                      child: Row(
                        children: [
                          IconBadge(
                            icon: Icons.account_balance_outlined,
                            color: color,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_currency.format(balance)} available',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: selected ? color : AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.brandGreen.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.arrow_downward,
                        size: 16,
                        color: AppColors.brandGreen,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Into: Petty Cash',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandGreenDeep,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const SectionLabel('DATE'),
                const SizedBox(height: 8),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppStyles.radiusField),
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(
                      AppStyles.radiusField,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppStyles.radiusField,
                        ),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 17,
                            color: AppColors.brandGreen,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _dateFormat.format(_selectedDate),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const SectionLabel('AMOUNT'),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: '\$0.00',
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const SectionLabel('NOTE (OPTIONAL)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(hintText: 'Add a note'),
                ),
                const SizedBox(height: 24),

                if (_errorMessage != null) ...[
                  ErrorNote(_errorMessage!),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Transfer'),
                  ),
                ),
              ],
            ),
    );
  }
}
