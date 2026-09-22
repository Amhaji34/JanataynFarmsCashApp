import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';

/// Which of the two summary totals (if any) an entry counts toward.
enum _EntryKind { fundAdd, transfer, other }

class _Entry {
  _Entry({
    required this.date,
    required this.createdAt,
    required this.label,
    required this.amount,
    required this.currency,
    required this.isPositive,
    required this.color,
    required this.icon,
    required this.kind,
  });

  final DateTime date;
  final DateTime createdAt;
  final String label;
  final double amount;
  final AppCurrency currency;
  final bool isPositive;
  final Color color;
  final IconData icon;
  final _EntryKind kind;

  /// Running balance, in this entry's own currency, immediately after
  /// this entry - computed once entries are known in chronological
  /// order. A SLSH entry never moves the USD running balance and vice
  /// versa, so each currency's running total is tracked independently
  /// even though both currencies' entries share one timeline.
  double balanceAfter = 0;
}

/// Ledger/history for a single account. Petty Cash's history also folds in
/// the main `transactions` table (expenses, payroll, loans, advances,
/// repayments) since that's what actually moves its balance day to day;
/// the other three accounts only ever see fund_add / transfer_out rows.
/// Every balance/total here is tracked per currency - USD and SLSH never
/// mix.
class AccountHistoryScreen extends StatefulWidget {
  const AccountHistoryScreen({
    super.key,
    required this.accountId,
    required this.accountName,
  });

  final String accountId;
  final String accountName;

  @override
  State<AccountHistoryScreen> createState() => _AccountHistoryScreenState();
}

class _AccountHistoryScreenState extends State<AccountHistoryScreen> {
  bool get _isPettyCash => widget.accountName == 'Petty Cash';

  bool _loading = true;
  String? _errorMessage;
  Map<AppCurrency, double> _balances = {};
  List<_Entry> _entries = [];
  DateTimeRange? _dateRange;

  final _dateFormat = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<_Entry> get _filteredEntries {
    if (_dateRange == null) return _entries;
    final start = DateTime(
      _dateRange!.start.year,
      _dateRange!.start.month,
      _dateRange!.start.day,
    );
    final end = DateTime(
      _dateRange!.end.year,
      _dateRange!.end.month,
      _dateRange!.end.day,
      23,
      59,
      59,
    );
    return _entries
        .where((e) => !e.date.isBefore(start) && !e.date.isAfter(end))
        .toList();
  }

  Map<AppCurrency, double> _sumByCurrency(bool Function(_Entry) matches) {
    final totals = {for (final c in AppCurrency.values) c: 0.0};
    for (final e in _filteredEntries.where(matches)) {
      totals[e.currency] = (totals[e.currency] ?? 0) + e.amount;
    }
    return totals;
  }

  Map<AppCurrency, double> get _totalAdded =>
      _sumByCurrency((e) => e.kind == _EntryKind.fundAdd);

  /// Petty Cash never has fund_add rows, so "Total added" is meaningless
  /// there - this sums the actual outflows (expense/payroll/loan/advance)
  /// instead.
  Map<AppCurrency, double> get _totalSpent =>
      _sumByCurrency((e) => e.kind == _EntryKind.other && !e.isPositive);

  Map<AppCurrency, double> get _totalTransferred =>
      _sumByCurrency((e) => e.kind == _EntryKind.transfer);

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  void _clearDateRange() => setState(() => _dateRange = null);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final accountsData = await supabase.from('accounts').select();
      final accounts = List<Map<String, dynamic>>.from(accountsData);
      final accountNameById = {
        for (final a in accounts) a['id'] as String: a['name'] as String,
      };

      final ledgerData = await supabase
          .from('account_transactions')
          .select()
          .eq('account_id', widget.accountId);
      final ledger = List<Map<String, dynamic>>.from(ledgerData);

      final entries = <_Entry>[];

      for (final t in ledger) {
        final amount = (t['amount'] as num).toDouble();
        final currency = AppCurrency.fromCode(t['currency'] as String?);
        final date = DateTime.parse(t['transaction_date'] as String);
        final createdAt = DateTime.parse(t['created_at'] as String);
        final type = t['type'] as String;
        final relatedName = accountNameById[t['related_account_id']];

        switch (type) {
          case 'fund_add':
            entries.add(
              _Entry(
                date: date,
                createdAt: createdAt,
                label: 'Funds added',
                amount: amount,
                currency: currency,
                isPositive: true,
                color: AppColors.cashIn,
                icon: Icons.add,
                kind: _EntryKind.fundAdd,
              ),
            );
            break;
          case 'transfer_out':
            entries.add(
              _Entry(
                date: date,
                createdAt: createdAt,
                label: 'Transferred to ${relatedName ?? 'Petty Cash'}',
                amount: amount,
                currency: currency,
                isPositive: false,
                color: AppColors.brandNavy,
                icon: Icons.arrow_upward,
                kind: _EntryKind.transfer,
              ),
            );
            break;
          case 'transfer_in':
            entries.add(
              _Entry(
                date: date,
                createdAt: createdAt,
                label: 'Transfer from ${relatedName ?? 'another account'}',
                amount: amount,
                currency: currency,
                isPositive: true,
                color: AppColors.cashIn,
                icon: Icons.arrow_downward,
                kind: _EntryKind.transfer,
              ),
            );
            break;
        }
      }

      final openingBalances = {for (final c in AppCurrency.values) c: 0.0};
      if (_isPettyCash) {
        final settingsRow = await supabase
            .from('settings')
            .select()
            .eq('key', 'opening_balance')
            .single();
        openingBalances[AppCurrency.usd] = (settingsRow['value'] as num)
            .toDouble();

        final txnsData = await supabase.from('transactions').select();
        for (final t in List<Map<String, dynamic>>.from(txnsData)) {
          final amount = (t['amount'] as num).toDouble();
          final currency = AppCurrency.fromCode(t['currency'] as String?);
          final date = DateTime.parse(t['transaction_date'] as String);
          final createdAt = DateTime.parse(t['created_at'] as String);
          final type = t['type'] as String;

          switch (type) {
            case 'expense':
              entries.add(
                _Entry(
                  date: date,
                  createdAt: createdAt,
                  label: 'Expense',
                  amount: amount,
                  currency: currency,
                  isPositive: false,
                  color: AppColors.expense,
                  icon: Icons.receipt_long_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'payroll':
              entries.add(
                _Entry(
                  date: date,
                  createdAt: createdAt,
                  label: 'Payroll',
                  amount: amount,
                  currency: currency,
                  isPositive: false,
                  color: AppColors.payroll,
                  icon: Icons.payments_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'loan':
              entries.add(
                _Entry(
                  date: date,
                  createdAt: createdAt,
                  label: 'Loan given',
                  amount: amount,
                  currency: currency,
                  isPositive: false,
                  color: AppColors.loan,
                  icon: Icons.pan_tool_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'advance':
              entries.add(
                _Entry(
                  date: date,
                  createdAt: createdAt,
                  label: 'Advance given',
                  amount: amount,
                  currency: currency,
                  isPositive: false,
                  color: AppColors.advance,
                  icon: Icons.pan_tool_alt_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'loan_repayment':
              entries.add(
                _Entry(
                  date: date,
                  createdAt: createdAt,
                  label: 'Loan repayment received',
                  amount: amount,
                  currency: currency,
                  isPositive: true,
                  color: AppColors.cashIn,
                  icon: Icons.south_west,
                  kind: _EntryKind.other,
                ),
              );
              break;
            // advance_deduction has no cash impact - excluded.
          }
        }
      }

      // Chronological (oldest first) so the running balance is meaningful,
      // then tag each entry with the balance immediately after it - one
      // running total per currency, tracked independently.
      entries.sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
      });

      final running = Map<AppCurrency, double>.from(openingBalances);
      for (final e in entries) {
        final updated =
            (running[e.currency] ?? 0) + (e.isPositive ? e.amount : -e.amount);
        running[e.currency] = updated;
        e.balanceAfter = updated;
      }

      final displayEntries = entries.reversed.toList();

      setState(() {
        _balances = running;
        _entries = displayEntries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load account history: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.accentFor(widget.accountName);
    final filtered = _filteredEntries;

    return Scaffold(
      appBar: AppBar(title: Text(widget.accountName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_errorMessage!)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  AppCard(
                    accent: color,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(
                              icon: Icons.account_balance_outlined,
                              color: color,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Current balance',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DualCurrencyStat(
                          amounts: _balances,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
                          spacing: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDateRange,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _dateRange == null
                                ? AppColors.inkSecondary
                                : AppColors.brandGreen,
                            backgroundColor: _dateRange == null
                                ? AppColors.surface
                                : AppColors.brandGreen.withValues(alpha: 0.08),
                            side: BorderSide(
                              color: _dateRange == null
                                  ? AppColors.hairline
                                  : AppColors.brandGreen.withValues(
                                      alpha: 0.35,
                                    ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 15,
                          ),
                          label: Text(
                            _dateRange == null
                                ? 'Filter by date'
                                : '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_dateRange != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: AppColors.inkMuted,
                          onPressed: _clearDateRange,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _dualStatCard(
                          icon: _isPettyCash ? Icons.trending_down : Icons.add,
                          label: _isPettyCash ? 'Total spent' : 'Total added',
                          amounts: _isPettyCash ? _totalSpent : _totalAdded,
                          color: _isPettyCash
                              ? AppColors.expense
                              : AppColors.cashIn,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _dualStatCard(
                          icon: Icons.sync_alt,
                          label: 'Total transferred',
                          amounts: _totalTransferred,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const SectionLabel('HISTORY'),
                  const SizedBox(height: 10),
                  if (filtered.isEmpty)
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: _entries.isEmpty
                          ? 'No activity yet'
                          : 'No activity in this range',
                      subtitle: _entries.isEmpty
                          ? 'Movements in this account will show up here.'
                          : 'Try a different date range.',
                    )
                  else
                    ...filtered.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              IconBadge(icon: e.icon, color: e.color),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.label,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _dateFormat.format(e.date),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${e.isPositive ? '+' : '-'}${formatMoney(e.amount, e.currency)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                      color: e.color,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Bal: ${formatMoney(e.balanceAfter, e.currency)}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _dualStatCard({
    required IconData icon,
    required String label,
    required Map<AppCurrency, double> amounts,
    required Color color,
  }) {
    return AppCard(
      accent: color,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 34, iconSize: 17),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.inkSecondary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 3),
          DualCurrencyStat(
            amounts: amounts,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
