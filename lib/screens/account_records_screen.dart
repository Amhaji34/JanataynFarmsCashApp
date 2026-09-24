import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';

/// One Payroll/Advances/Loans record, built by report_screen.dart from
/// whatever's currently filtered - this screen never fetches on its
/// own. Mirrors CategoryInvoice's shape (category_invoices_screen.dart)
/// but generalized to any of the three non-Expenses account tabs.
class AccountRecord {
  AccountRecord({
    required this.title,
    required this.date,
    required this.amount,
    required this.currency,
    required this.color,
    required this.icon,
    required this.isPositive,
    required this.isNeutral,
    required this.note,
  });

  /// Already fully formed (e.g. "John Doe · Advance given") - built by
  /// report_screen.dart's existing `_rowTitle()`.
  final String title;
  final DateTime date;
  final double amount;
  final AppCurrency currency;
  final Color color;
  final IconData icon;

  /// Shown with a leading "+" (cash coming in, e.g. a loan repayment).
  final bool isPositive;

  /// Shown with no sign at all (no real cash moves, e.g. an advance
  /// deduction).
  final bool isNeutral;

  final String note;
}

/// Every record in the currently filtered Payroll/Advances/Loans view,
/// as cards - reached from report_screen.dart's "View N records"
/// button. Tapping a card opens a bottom sheet with that record's full
/// detail.
class AccountRecordsScreen extends StatelessWidget {
  const AccountRecordsScreen({
    super.key,
    required this.accountName,
    required this.records,
  });

  final String accountName;
  final List<AccountRecord> records;

  static final _dateFormat = DateFormat('MMM d, yyyy');

  void _openDetail(BuildContext context, AccountRecord record) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordDetailSheet(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(accountName)),
      body: records.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No records',
              subtitle: 'No records for the current filters.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final record = records[index];
                return AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  onTap: () => _openDetail(context, record),
                  child: Row(
                    children: [
                      IconBadge(icon: record.icon, color: record.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _dateFormat.format(record.date),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        record.isNeutral
                            ? formatMoney(record.amount, record.currency)
                            : '${record.isPositive ? '+' : '-'}'
                                  '${formatMoney(record.amount, record.currency)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: record.isNeutral
                              ? AppColors.inkMuted
                              : record.color,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _RecordDetailSheet extends StatelessWidget {
  const _RecordDetailSheet({required this.record});

  final AccountRecord record;

  static final _dateFormat = DateFormat('MMM d, yyyy');

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconBadge(icon: record.icon, color: record.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        formatMoney(record.amount, record.currency),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: record.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _row('Details', record.title),
                _row('Date', _dateFormat.format(record.date)),
                if (record.note.trim().isNotEmpty)
                  _row('Note', record.note.trim()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
