import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';

/// One expense-category invoice - a single `transaction_items` row,
/// flattened together with its parent transaction's date/currency/note
/// for display. Built by report_screen.dart from whatever's currently
/// filtered, so this screen never fetches on its own.
class CategoryInvoice {
  CategoryInvoice({
    required this.transactionId,
    required this.itemId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.itemNote,
    required this.transactionNote,
    required this.otherCategories,
  });

  final String transactionId;
  final String itemId;
  final DateTime date;
  final double amount;
  final AppCurrency currency;
  final String? itemNote;
  final String transactionNote;

  /// Other categories on the same (multi-invoice) transaction, if any -
  /// shown in the detail sheet so it's clear this invoice was part of a
  /// larger payment, not a standalone one.
  final List<String> otherCategories;
}

/// Every invoice (transaction_items row) in one expense category, as
/// cards - reached from report_screen.dart's "View invoices" button,
/// shown once a single category is selected. Tapping a card opens a
/// bottom sheet with that invoice's full detail.
class CategoryInvoicesScreen extends StatelessWidget {
  const CategoryInvoicesScreen({
    super.key,
    required this.categoryName,
    required this.invoices,
  });

  final String categoryName;
  final List<CategoryInvoice> invoices;

  static final _dateFormat = DateFormat('MMM d, yyyy');

  void _openDetail(BuildContext context, CategoryInvoice invoice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _InvoiceDetailSheet(categoryName: categoryName, invoice: invoice),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: invoices.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No invoices',
              subtitle: 'No invoices in this category for the current filters.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                AppCard(
                  accent: AppColors.expense,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconBadge(
                        icon: Icons.receipt_long_outlined,
                        color: AppColors.expense,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${invoices.length} invoice${invoices.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            DualCurrencyStat(
                              amounts: {
                                for (final c in AppCurrency.values)
                                  c: invoices
                                      .where((i) => i.currency == c)
                                      .fold<double>(
                                        0,
                                        (sum, i) => sum + i.amount,
                                      ),
                              },
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...invoices.map(
                  (invoice) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () => _openDetail(context, invoice),
                      child: Row(
                        children: [
                          IconBadge(
                            icon: Icons.receipt_long_outlined,
                            color: AppColors.expense,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (invoice.itemNote?.trim().isNotEmpty ?? false)
                                      ? invoice.itemNote!.trim()
                                      : (invoice.transactionNote
                                                .trim()
                                                .isNotEmpty
                                            ? invoice.transactionNote.trim()
                                            : categoryName),
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
                                  _dateFormat.format(invoice.date),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatMoney(invoice.amount, invoice.currency),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InvoiceDetailSheet extends StatelessWidget {
  const _InvoiceDetailSheet({
    required this.categoryName,
    required this.invoice,
  });

  final String categoryName;
  final CategoryInvoice invoice;

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
                    IconBadge(
                      icon: Icons.receipt_long_outlined,
                      color: AppColors.expense,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        formatMoney(invoice.amount, invoice.currency),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.expense,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _row('Category', categoryName),
                _row('Date', _dateFormat.format(invoice.date)),
                if ((invoice.itemNote?.trim().isNotEmpty ?? false))
                  _row('Invoice note', invoice.itemNote!.trim()),
                if (invoice.transactionNote.trim().isNotEmpty)
                  _row('Payment note', invoice.transactionNote.trim()),
                if (invoice.otherCategories.isNotEmpty)
                  _row(
                    'Also covers',
                    'This payment also included: '
                        '${invoice.otherCategories.join(', ')}',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
