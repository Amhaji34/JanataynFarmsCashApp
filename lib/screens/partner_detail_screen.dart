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
    required this.isPositive,
  });

  final DateTime date;
  final String label;
  final double amount;
  final AppCurrency currency;
  final Color color;
  final IconData icon;
  final bool isPositive;
}

/// One partner's outstanding loan balance and history: every loan given
/// (increases what they owe) and every repayment (reduces it), merged
/// and sorted newest first. A partner can owe in either currency, so
/// the balance is tracked per currency — never blended.
class PartnerDetailScreen extends StatefulWidget {
  const PartnerDetailScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
  });

  final String partnerId;
  final String partnerName;

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> {
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
          .eq('related_partner_id', widget.partnerId);
      final txns = List<Map<String, dynamic>>.from(data);

      final lent = {for (final c in AppCurrency.values) c: 0.0};
      final repaid = {for (final c in AppCurrency.values) c: 0.0};
      final entries = <_Entry>[];

      for (final t in txns) {
        final type = t['type'] as String;
        final amount = (t['amount'] as num).toDouble();
        final date = DateTime.parse(t['transaction_date'] as String);
        final currency = AppCurrency.fromCode(t['currency'] as String?);
        final note = (t['note'] as String? ?? '').trim();

        switch (type) {
          case 'loan':
            lent[currency] = (lent[currency] ?? 0) + amount;
            entries.add(
              _Entry(
                date: date,
                label: note.isEmpty ? 'Loan given' : 'Loan given — $note',
                amount: amount,
                currency: currency,
                color: AppColors.loan,
                icon: Icons.call_made,
                isPositive: false,
              ),
            );
            break;
          case 'loan_repayment':
            repaid[currency] = (repaid[currency] ?? 0) + amount;
            entries.add(
              _Entry(
                date: date,
                label: note.isEmpty ? 'Repayment' : 'Repayment — $note',
                amount: amount,
                currency: currency,
                color: AppColors.cashIn,
                icon: Icons.call_received,
                isPositive: true,
              ),
            );
            break;
        }
      }

      entries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _owed = {
          for (final c in AppCurrency.values)
            c: (lent[c] ?? 0) - (repaid[c] ?? 0),
        };
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load partner history: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDebt = _owed.values.any((v) => v > 0.01);

    return Scaffold(
      appBar: AppBar(title: Text(widget.partnerName)),
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
                    accent: hasDebt ? AppColors.loan : AppColors.cashIn,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(
                              icon: Icons.account_balance_wallet_outlined,
                              color: hasDebt
                                  ? AppColors.loan
                                  : AppColors.cashIn,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              hasDebt
                                  ? 'Owes (outstanding loan)'
                                  : 'Loan settled',
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
                          'Loans and repayments for this partner will '
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
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
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
                                '${e.isPositive ? '+' : '-'}${formatMoney(e.amount, e.currency)}',
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
