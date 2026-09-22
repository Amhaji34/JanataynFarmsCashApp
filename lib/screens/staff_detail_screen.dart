import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';

class _Entry {
  _Entry({
    required this.date,
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    required this.icon,
    required this.isNeutral,
  });

  final DateTime date;
  final String label;
  final double amount;
  final AppCurrency currency;
  final Color color;
  final IconData icon;

  /// advance_deduction moves no real cash (see claude.md's Design
  /// language section) so it's shown without a +/- sign, same as
  /// everywhere else in the app.
  final bool isNeutral;
}

/// One staff member's advance balance and history: every advance given
/// (increases what they owe), every deduction taken from payroll
/// (reduces it), and payroll paid, merged and sorted newest first. A
/// staff member can be advanced/paid in either currency, so the owed
/// balance is tracked per currency — never blended.
class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({
    super.key,
    required this.staffId,
    required this.staffName,
    required this.baseSalary,
    required this.baseSalaryCurrency,
  });

  final String staffId;
  final String staffName;
  final double baseSalary;
  final AppCurrency baseSalaryCurrency;

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  bool _loading = true;
  String? _errorMessage;
  Map<AppCurrency, double> _owed = {};
  List<_Entry> _entries = [];

  final _dateFormat = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('transactions')
          .select()
          .eq('related_staff_id', widget.staffId);
      final txns = List<Map<String, dynamic>>.from(data);

      final given = {for (final c in AppCurrency.values) c: 0.0};
      final deducted = {for (final c in AppCurrency.values) c: 0.0};
      final entries = <_Entry>[];

      for (final t in txns) {
        final type = t['type'] as String;
        final amount = (t['amount'] as num).toDouble();
        final date = DateTime.parse(t['transaction_date'] as String);
        final currency = AppCurrency.fromCode(t['currency'] as String?);

        switch (type) {
          case 'advance':
            given[currency] = (given[currency] ?? 0) + amount;
            entries.add(
              _Entry(
                date: date,
                label: 'Advance given',
                amount: amount,
                currency: currency,
                color: AppColors.advance,
                icon: Icons.pan_tool_alt_outlined,
                isNeutral: false,
              ),
            );
            break;
          case 'advance_deduction':
            deducted[currency] = (deducted[currency] ?? 0) + amount;
            entries.add(
              _Entry(
                date: date,
                label: 'Deducted from payroll',
                amount: amount,
                currency: currency,
                color: AppColors.neutral,
                icon: Icons.sync_alt,
                isNeutral: true,
              ),
            );
            break;
          case 'payroll':
            entries.add(
              _Entry(
                date: date,
                label: 'Payroll paid',
                amount: amount,
                currency: currency,
                color: AppColors.payroll,
                icon: Icons.payments_outlined,
                isNeutral: false,
              ),
            );
            break;
        }
      }

      entries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _owed = {
          for (final c in AppCurrency.values)
            c: (given[c] ?? 0) - (deducted[c] ?? 0),
        };
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load staff history: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDebt = _owed.values.any((v) => v > 0.01);

    return Scaffold(
      appBar: AppBar(title: Text(widget.staffName)),
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
                    accent: hasDebt ? AppColors.advance : AppColors.cashIn,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(
                              icon: Icons.account_balance_wallet_outlined,
                              color: hasDebt
                                  ? AppColors.advance
                                  : AppColors.cashIn,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              hasDebt
                                  ? 'Owes (outstanding advance)'
                                  : 'Advance settled',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DualCurrencyStat(
                          amounts: {
                            for (final c in AppCurrency.values)
                              c: (_owed[c] ?? 0).abs(),
                          },
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
                          spacing: 4,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Base salary: ${formatMoney(widget.baseSalary, widget.baseSalaryCurrency)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('HISTORY'),
                  const SizedBox(height: 10),
                  if (_entries.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No activity yet',
                      subtitle:
                          'Payroll and advances for this staff member will '
                          'show up here.',
                    )
                  else
                    ..._entries.map(
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
                                        fontSize: 11.5,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                e.isNeutral
                                    ? formatMoney(e.amount, e.currency)
                                    : '-${formatMoney(e.amount, e.currency)}',
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
