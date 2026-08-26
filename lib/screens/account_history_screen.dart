import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Which of the two summary totals (if any) an entry counts toward.
enum _EntryKind { fundAdd, transfer, other }

class _Entry {
  _Entry({
    required this.date,
    required this.label,
    required this.amount,
    required this.isPositive,
    required this.color,
    required this.icon,
    required this.kind,
  });

  final DateTime date;
  final String label;
  final double amount;
  final bool isPositive;
  final Color color;
  final IconData icon;
  final _EntryKind kind;
}

/// Ledger/history for a single account. Petty Cash's history also folds in
/// the main `transactions` table (expenses, payroll, loans, advances,
/// repayments) since that's what actually moves its balance day to day;
/// the other three accounts only ever see fund_add / transfer_out rows.
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
  double _balance = 0;
  List<_Entry> _entries = [];
  DateTimeRange? _dateRange;

  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
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
        .where(
          (e) =>
              !e.date.isBefore(start) && !e.date.isAfter(end),
        )
        .toList();
  }

  double get _totalAdded => _filteredEntries
      .where((e) => e.kind == _EntryKind.fundAdd)
      .fold(0, (sum, e) => sum + e.amount);

  double get _totalTransferred => _filteredEntries
      .where((e) => e.kind == _EntryKind.transfer)
      .fold(0, (sum, e) => sum + e.amount);

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
      double balance = 0;

      for (final t in ledger) {
        final amount = (t['amount'] as num).toDouble();
        final date = DateTime.parse(t['transaction_date'] as String);
        final type = t['type'] as String;
        final relatedName = accountNameById[t['related_account_id']];

        switch (type) {
          case 'fund_add':
            balance += amount;
            entries.add(
              _Entry(
                date: date,
                label: 'Funds added',
                amount: amount,
                isPositive: true,
                color: AppColors.cashIn,
                icon: Icons.add,
                kind: _EntryKind.fundAdd,
              ),
            );
            break;
          case 'transfer_out':
            balance -= amount;
            entries.add(
              _Entry(
                date: date,
                label: 'Transferred to ${relatedName ?? 'Petty Cash'}',
                amount: amount,
                isPositive: false,
                color: AppColors.brandNavy,
                icon: Icons.arrow_upward,
                kind: _EntryKind.transfer,
              ),
            );
            break;
          case 'transfer_in':
            balance += amount;
            entries.add(
              _Entry(
                date: date,
                label: 'Transfer from ${relatedName ?? 'another account'}',
                amount: amount,
                isPositive: true,
                color: AppColors.cashIn,
                icon: Icons.arrow_downward,
                kind: _EntryKind.transfer,
              ),
            );
            break;
        }
      }

      if (_isPettyCash) {
        final settingsRow = await supabase
            .from('settings')
            .select()
            .eq('key', 'opening_balance')
            .single();
        balance += (settingsRow['value'] as num).toDouble();

        final txnsData = await supabase.from('transactions').select();
        for (final t in List<Map<String, dynamic>>.from(txnsData)) {
          final amount = (t['amount'] as num).toDouble();
          final date = DateTime.parse(t['transaction_date'] as String);
          final type = t['type'] as String;

          switch (type) {
            case 'expense':
              balance -= amount;
              entries.add(
                _Entry(
                  date: date,
                  label: 'Expense',
                  amount: amount,
                  isPositive: false,
                  color: AppColors.expense,
                  icon: Icons.receipt_long_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'payroll':
              balance -= amount;
              entries.add(
                _Entry(
                  date: date,
                  label: 'Payroll',
                  amount: amount,
                  isPositive: false,
                  color: AppColors.payroll,
                  icon: Icons.payments_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'loan':
              balance -= amount;
              entries.add(
                _Entry(
                  date: date,
                  label: 'Loan given',
                  amount: amount,
                  isPositive: false,
                  color: AppColors.loan,
                  icon: Icons.pan_tool_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'advance':
              balance -= amount;
              entries.add(
                _Entry(
                  date: date,
                  label: 'Advance given',
                  amount: amount,
                  isPositive: false,
                  color: AppColors.advance,
                  icon: Icons.pan_tool_alt_outlined,
                  kind: _EntryKind.other,
                ),
              );
              break;
            case 'loan_repayment':
              balance += amount;
              entries.add(
                _Entry(
                  date: date,
                  label: 'Loan repayment received',
                  amount: amount,
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

      entries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _balance = balance;
        _entries = entries;
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
                        Text(
                          _currency.format(_balance),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
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
                                : AppColors.brandGreen.withValues(
                                    alpha: 0.08,
                                  ),
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
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.add,
                          label: 'Total added',
                          value: _currency.format(_totalAdded),
                          color: AppColors.cashIn,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          icon: Icons.sync_alt,
                          label: 'Total transferred',
                          value: _currency.format(_totalTransferred),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                              Text(
                                '${e.isPositive ? '+' : '-'}${_currency.format(e.amount)}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  color: e.color,
                                ),
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
}
