import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class _Entry {
  _Entry({
    required this.date,
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    required this.isNeutral,
  });

  final DateTime date;
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  /// advance_deduction moves no real cash (see claude.md's Design
  /// language section) so it's shown without a +/- sign, same as
  /// everywhere else in the app.
  final bool isNeutral;
}

/// One staff member's advance balance and history: every advance given
/// (increases what they owe), every deduction taken from payroll
/// (reduces it), and payroll paid, merged and sorted newest first.
class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({
    super.key,
    required this.staffId,
    required this.staffName,
    required this.baseSalary,
  });

  final String staffId;
  final String staffName;
  final double baseSalary;

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  bool _loading = true;
  String? _errorMessage;
  double _owed = 0;
  List<_Entry> _entries = [];

  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
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

      double given = 0;
      double deducted = 0;
      final entries = <_Entry>[];

      for (final t in txns) {
        final type = t['type'] as String;
        final amount = (t['amount'] as num).toDouble();
        final date = DateTime.parse(t['transaction_date'] as String);

        switch (type) {
          case 'advance':
            given += amount;
            entries.add(
              _Entry(
                date: date,
                label: 'Advance given',
                amount: amount,
                color: AppColors.advance,
                icon: Icons.pan_tool_alt_outlined,
                isNeutral: false,
              ),
            );
            break;
          case 'advance_deduction':
            deducted += amount;
            entries.add(
              _Entry(
                date: date,
                label: 'Deducted from payroll',
                amount: amount,
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
        _owed = given - deducted;
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
    final hasDebt = _owed > 0.01;

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
                        Text(
                          _currency.format(_owed.abs()),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Base salary: ${_currency.format(widget.baseSalary)}',
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
                                    ? _currency.format(e.amount)
                                    : '-${_currency.format(e.amount)}',
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
