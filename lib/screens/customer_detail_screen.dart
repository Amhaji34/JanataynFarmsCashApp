import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'record_payment_screen.dart';

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

/// One customer's balance and full history: every harvest sold to them
/// (increases what they owe) and every payment they've made (reduces
/// it), merged and sorted newest first. A customer can owe in either
/// currency (or both) so the balance is tracked per currency throughout
/// — never blended into one converted number.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
  });

  final String customerId;
  final String customerName;
  final String? customerPhone;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
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
      final salesData = await supabase
          .from('harvest_sales')
          .select()
          .eq('customer_id', widget.customerId);
      final sales = List<Map<String, dynamic>>.from(salesData);

      final paymentsData = await supabase
          .from('customer_payments')
          .select()
          .eq('customer_id', widget.customerId);
      final payments = List<Map<String, dynamic>>.from(paymentsData);

      final sold = {for (final c in AppCurrency.values) c: 0.0};
      final paid = {for (final c in AppCurrency.values) c: 0.0};
      final entries = <_Entry>[];

      for (final h in sales) {
        final kg = (h['kg_sold'] as num).toDouble();
        final pricePerKg = (h['price_per_kg'] as num).toDouble();
        final transportFee = (h['transport_fee'] as num? ?? 0).toDouble();
        final owed = (kg * pricePerKg - transportFee).clamp(
          0.0,
          double.infinity,
        );
        final currency = AppCurrency.fromCode(h['currency'] as String?);
        sold[currency] = (sold[currency] ?? 0) + owed;
        entries.add(
          _Entry(
            date: DateTime.parse(h['sale_date'] as String),
            label: 'Harvest sale',
            subtitle: transportFee > 0
                ? '${kg.toStringAsFixed(1)} kg @ ${formatMoney(pricePerKg, currency)}/kg '
                      '(−${formatMoney(transportFee, currency)} transport)'
                : '${kg.toStringAsFixed(1)} kg @ ${formatMoney(pricePerKg, currency)}/kg',
            amount: owed,
            currency: currency,
            isPositive: false,
            color: AppColors.brandGreenLight,
            icon: Icons.eco_outlined,
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
            label: 'Payment received',
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
            c: (sold[c] ?? 0) - (paid[c] ?? 0),
        };
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load customer history: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openRecordPayment() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordPaymentScreen(
          customerId: widget.customerId,
          customerName: widget.customerName,
          outstandingByCurrency: _owed,
        ),
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasDebt = _owed.values.any((v) => v > 0.01);

    return Scaffold(
      appBar: AppBar(title: Text(widget.customerName)),
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
                              hasDebt ? 'Owes' : 'Balance settled',
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
                        if (widget.customerPhone != null &&
                            widget.customerPhone!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.customerPhone!,
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
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _openRecordPayment,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Record payment'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const SectionLabel('HISTORY'),
                  const SizedBox(height: 10),
                  if (_entries.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No activity yet',
                      subtitle: 'Harvest sales and payments will show up here.',
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
