import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'add_purchase_screen.dart';
import 'record_supplier_payment_screen.dart';

class _Entry {
  _Entry({
    required this.date,
    required this.label,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.isPositive,
    required this.color,
    required this.icon,
  });

  final DateTime date;
  final String label;
  final String subtitle;
  final double amount;
  final AppCurrency currency;
  final bool isPositive;
  final Color color;
  final IconData icon;
}

/// One supplier's balance and full history: every purchase made from
/// them (increases what's owed) and every payment made (reduces it),
/// merged and sorted newest first. A supplier can be owed in either
/// currency (or both), so the balance is tracked per currency throughout
/// — never blended into one converted number.
class SupplierDetailScreen extends StatefulWidget {
  const SupplierDetailScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
    this.supplierPhone,
  });

  final String supplierId;
  final String supplierName;
  final String? supplierPhone;

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  bool _loading = true;
  String? _errorMessage;
  Map<AppCurrency, double> _owed = {};
  List<_Entry> _entries = [];
  String? _role;

  final _dateFormat = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _loadRole();
    _load();
  }

  Future<void> _loadRole() async {
    final userId = supabase.auth.currentUser!.id;
    final profile = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .single();
    if (mounted) setState(() => _role = profile['role'] as String?);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final purchasesData = await supabase
          .from('supplier_purchases')
          .select()
          .eq('supplier_id', widget.supplierId);
      final purchases = List<Map<String, dynamic>>.from(purchasesData);

      final paymentsData = await supabase
          .from('supplier_payments')
          .select()
          .eq('supplier_id', widget.supplierId);
      final payments = List<Map<String, dynamic>>.from(paymentsData);

      final bought = {for (final c in AppCurrency.values) c: 0.0};
      final paid = {for (final c in AppCurrency.values) c: 0.0};
      final entries = <_Entry>[];

      for (final p in purchases) {
        final amount = (p['amount'] as num).toDouble();
        final currency = AppCurrency.fromCode(p['currency'] as String?);
        bought[currency] = (bought[currency] ?? 0) + amount;
        entries.add(
          _Entry(
            date: DateTime.parse(p['purchase_date'] as String),
            label: p['item'] as String,
            subtitle: (p['note'] as String? ?? '').trim().isNotEmpty
                ? (p['note'] as String).trim()
                : 'Purchase',
            amount: amount,
            currency: currency,
            isPositive: false,
            color: AppColors.expense,
            icon: Icons.shopping_bag_outlined,
          ),
        );
      }

      for (final p in payments) {
        final amount = (p['amount'] as num).toDouble();
        final currency = AppCurrency.fromCode(p['currency'] as String?);
        paid[currency] = (paid[currency] ?? 0) + amount;
        entries.add(
          _Entry(
            date: DateTime.parse(p['payment_date'] as String),
            label: 'Payment made',
            subtitle: (p['note'] as String? ?? '').trim().isNotEmpty
                ? (p['note'] as String).trim()
                : 'Paid toward balance',
            amount: amount,
            currency: currency,
            isPositive: true,
            color: AppColors.cashIn,
            icon: Icons.check_circle_outline,
          ),
        );
      }

      entries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _owed = {
          for (final c in AppCurrency.values)
            c: (bought[c] ?? 0) - (paid[c] ?? 0),
        };
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load supplier history: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openAddPurchase() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AddPurchaseScreen(preselectedSupplierId: widget.supplierId),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _openRecordPayment() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordSupplierPaymentScreen(
          supplierId: widget.supplierId,
          supplierName: widget.supplierName,
          owedByCurrency: _owed,
        ),
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasDebt = _owed.values.any((v) => v > 0.01);

    return Scaffold(
      appBar: AppBar(title: Text(widget.supplierName)),
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
                    accent: hasDebt ? AppColors.expense : AppColors.cashIn,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(
                              icon: Icons.account_balance_wallet_outlined,
                              color: hasDebt
                                  ? AppColors.expense
                                  : AppColors.cashIn,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              hasDebt ? 'You owe' : 'Balance settled',
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
                          amounts: {
                            for (final c in AppCurrency.values)
                              c: (_owed[c] ?? 0).abs(),
                          },
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
                          spacing: 4,
                        ),
                        if (widget.supplierPhone != null &&
                            widget.supplierPhone!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.supplierPhone!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_role == 'admin') ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: _openAddPurchase,
                              icon: const Icon(
                                Icons.shopping_bag_outlined,
                                size: 18,
                              ),
                              label: const Text('Add purchase'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _openRecordPayment,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Record payment'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  const SectionLabel('HISTORY'),
                  const SizedBox(height: 10),
                  if (_entries.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No activity yet',
                      subtitle: 'Purchases and payments will show up here.',
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
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      e.subtitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _dateFormat.format(e.date),
                                      style: TextStyle(
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
