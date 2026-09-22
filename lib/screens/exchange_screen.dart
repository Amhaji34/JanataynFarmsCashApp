import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';

/// Converts part of one account's existing balance from one currency to
/// the other (e.g. USD cash on hand exchanged for SLSH from a money
/// changer, or vice versa). There is no exchange rate stored anywhere in
/// this app - the user enters both the amount given and the amount
/// received directly, the same way the exchange actually happens in
/// person. Writes two account_transactions rows on the SAME account: an
/// exchange_out in the source currency and an exchange_in in the
/// destination currency - not a transfer between accounts, just a
/// currency swap within one.
class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  static const _accountOrder = ['Investment', 'Loans', 'Revenue', 'Petty Cash'];

  bool _loadingAccounts = true;
  String? _loadError;
  List<Map<String, dynamic>> _accounts = [];

  /// accountId -> {currency -> balance}.
  Map<String, Map<AppCurrency, double>> _balances = {};

  String? _selectedAccountId;
  AppCurrency _fromCurrency = AppCurrency.usd;
  AppCurrency get _toCurrency =>
      _fromCurrency == AppCurrency.usd ? AppCurrency.slsh : AppCurrency.usd;

  final _giveController = TextEditingController();
  final _receiveController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');

  bool _saving = false;
  String? _errorMessage;

  double get _give => double.tryParse(_giveController.text) ?? 0;
  double get _receive => double.tryParse(_receiveController.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _giveController.dispose();
    _receiveController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() => _loadingAccounts = true);
    try {
      final accountsData = await supabase.from('accounts').select();
      final accounts = List<Map<String, dynamic>>.from(accountsData)
        ..sort(
          (a, b) => _accountOrder
              .indexOf(a['name'] as String)
              .compareTo(_accountOrder.indexOf(b['name'] as String)),
        );
      final pettyCash = accounts.firstWhere((a) => a['name'] == 'Petty Cash');
      final pettyCashId = pettyCash['id'] as String;

      final ledgerData = await supabase.from('account_transactions').select();
      final ledger = List<Map<String, dynamic>>.from(ledgerData);

      final balances = <String, Map<AppCurrency, double>>{};
      for (final account in accounts) {
        final id = account['id'] as String;
        final byCurrency = {for (final c in AppCurrency.values) c: 0.0};
        for (final t in ledger) {
          if (t['account_id'] != id) continue;
          final currency = AppCurrency.fromCode(t['currency'] as String?);
          final amount = (t['amount'] as num).toDouble();
          if (t['type'] == 'fund_add' ||
              t['type'] == 'transfer_in' ||
              t['type'] == 'exchange_in') {
            byCurrency[currency] = (byCurrency[currency] ?? 0) + amount;
          } else if (t['type'] == 'transfer_out' ||
              t['type'] == 'exchange_out') {
            byCurrency[currency] = (byCurrency[currency] ?? 0) - amount;
          }
        }
        balances[id] = byCurrency;
      }

      // Petty Cash's balance also folds in the opening balance and the
      // main transactions ledger - same formula as everywhere else this
      // app computes it (dashboard, account history, transfer screen).
      final settingsRow = await supabase
          .from('settings')
          .select()
          .eq('key', 'opening_balance')
          .single();
      final pettyCashBalance = balances[pettyCashId]!;
      pettyCashBalance[AppCurrency.usd] =
          (pettyCashBalance[AppCurrency.usd] ?? 0) +
          (settingsRow['value'] as num).toDouble();
      final txnsData = await supabase.from('transactions').select();
      for (final t in List<Map<String, dynamic>>.from(txnsData)) {
        final currency = AppCurrency.fromCode(t['currency'] as String?);
        final amount = (t['amount'] as num).toDouble();
        switch (t['type'] as String) {
          case 'expense':
          case 'payroll':
          case 'loan':
          case 'advance':
            pettyCashBalance[currency] =
                (pettyCashBalance[currency] ?? 0) - amount;
            break;
          case 'loan_repayment':
            pettyCashBalance[currency] =
                (pettyCashBalance[currency] ?? 0) + amount;
            break;
        }
      }

      setState(() {
        _accounts = accounts;
        _balances = balances;
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
      setState(() => _errorMessage = 'Select an account.');
      return;
    }
    if (_give <= 0) {
      setState(() => _errorMessage = 'Enter the amount you\'re giving.');
      return;
    }
    if (_receive <= 0) {
      setState(() => _errorMessage = 'Enter the amount you\'re receiving.');
      return;
    }
    final available = _balances[_selectedAccountId]?[_fromCurrency] ?? 0;
    if (_give > available + 0.01) {
      setState(
        () => _errorMessage =
            'Only ${formatMoney(available, _fromCurrency)} available in '
            'this account.',
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
          'type': 'exchange_out',
          'amount': _give,
          'currency': _fromCurrency.code,
          'transaction_date': date,
          'note': note,
        },
        {
          'account_id': _selectedAccountId,
          'type': 'exchange_in',
          'amount': _receive,
          'currency': _toCurrency.code,
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
      appBar: AppBar(title: const Text('Exchange currency')),
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
                const SectionLabel('ACCOUNT'),
                const SizedBox(height: 8),
                ..._accounts.map((a) {
                  final id = a['id'] as String;
                  final name = a['name'] as String;
                  final selected = id == _selectedAccountId;
                  final color = AppColors.accentFor(name);
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
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
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
                const SizedBox(height: 16),

                const SectionLabel('DIRECTION'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _directionButton(
                        label: 'USD → SLSH',
                        selected: _fromCurrency == AppCurrency.usd,
                        onTap: () =>
                            setState(() => _fromCurrency = AppCurrency.usd),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _directionButton(
                        label: 'SLSH → USD',
                        selected: _fromCurrency == AppCurrency.slsh,
                        onTap: () =>
                            setState(() => _fromCurrency = AppCurrency.slsh),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_selectedAccountId != null) ...[
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
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: AppColors.brandGreen,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${formatMoney(_balances[_selectedAccountId]?[_fromCurrency] ?? 0, _fromCurrency)} '
                            'available in ${_fromCurrency.code}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brandGreenDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                SectionLabel('YOU GIVE (${_fromCurrency.code})'),
                const SizedBox(height: 8),
                TextField(
                  controller: _giveController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: '${_fromCurrency.symbol}0',
                    prefixText: '${_fromCurrency.symbol} ',
                    prefixStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                SectionLabel('YOU RECEIVE (${_toCurrency.code})'),
                const SizedBox(height: 8),
                TextField(
                  controller: _receiveController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: '${_toCurrency.symbol}0',
                    prefixText: '${_toCurrency.symbol} ',
                    prefixStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
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
                    borderRadius: BorderRadius.circular(AppStyles.radiusField),
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
                        : const Text('Exchange'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _directionButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? AppColors.brandGreen.withValues(alpha: 0.10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusField),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
            border: Border.all(
              color: selected
                  ? AppColors.brandGreen.withValues(alpha: 0.4)
                  : AppColors.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.currency_exchange,
                size: 16,
                color: selected ? AppColors.brandGreen : AppColors.inkMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.brandGreenDeep : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
