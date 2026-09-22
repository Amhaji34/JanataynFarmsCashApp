import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'customer_detail_screen.dart';

/// Lists customers with their outstanding balance (what they still owe
/// for harvest sales), and doubles as the "create a customer" screen via
/// the add-form at the top - same combined list+add pattern as
/// staff_screen.dart / partners_screen.dart.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _customers = [];
  Map<String, Map<AppCurrency, double>> _owed = {};

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  bool _adding = false;
  String? _addError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final customersData = await supabase
          .from('customers')
          .select()
          .order('name');
      final customers = List<Map<String, dynamic>>.from(customersData);

      final harvestsData = await supabase
          .from('harvests')
          .select('customer_id, kg_harvested, price_per_kg, currency');
      final harvests = List<Map<String, dynamic>>.from(harvestsData);

      final paymentsData = await supabase
          .from('customer_payments')
          .select('customer_id, amount, currency');
      final payments = List<Map<String, dynamic>>.from(paymentsData);

      final owed = <String, Map<AppCurrency, double>>{};
      for (final customer in customers) {
        final id = customer['id'] as String;
        final sold = {for (final c in AppCurrency.values) c: 0.0};
        for (final h in harvests) {
          if (h['customer_id'] != id) continue;
          final currency = AppCurrency.fromCode(h['currency'] as String?);
          sold[currency] =
              (sold[currency] ?? 0) +
              (h['kg_harvested'] as num).toDouble() *
                  (h['price_per_kg'] as num).toDouble();
        }
        final paid = {for (final c in AppCurrency.values) c: 0.0};
        for (final p in payments) {
          if (p['customer_id'] != id) continue;
          final currency = AppCurrency.fromCode(p['currency'] as String?);
          paid[currency] =
              (paid[currency] ?? 0) + (p['amount'] as num).toDouble();
        }
        owed[id] = {
          for (final c in AppCurrency.values)
            c: (sold[c] ?? 0) - (paid[c] ?? 0),
        };
      }

      setState(() {
        _customers = customers;
        _owed = owed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load customers: $e';
        _loading = false;
      });
    }
  }

  Future<void> _addCustomer() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      await supabase.from('customers').insert({
        'name': name,
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      });
      _nameController.clear();
      _phoneController.clear();
      _noteController.clear();
      await _load();
    } catch (e) {
      setState(() => _addError = 'Could not add customer: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openCustomer(Map<String, dynamic> customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(
          customerId: customer['id'] as String,
          customerName: customer['name'] as String,
          customerPhone: customer['phone'] as String?,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
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
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('ADD A CUSTOMER'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Customer name',
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.person_add_alt_outlined,
                              size: 19,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            hintText: 'Phone (optional)',
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.phone_outlined,
                              size: 19,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _noteController,
                          decoration: const InputDecoration(
                            hintText: 'Note (optional)',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: _adding ? null : _addCustomer,
                            child: _adding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Add customer'),
                          ),
                        ),
                        if (_addError != null) ...[
                          const SizedBox(height: 10),
                          ErrorNote(_addError!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_customers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: SectionLabel(
                        'ALL CUSTOMERS',
                        trailing: Text(
                          '${_customers.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  if (_customers.isEmpty)
                    const EmptyState(
                      icon: Icons.groups_outlined,
                      title: 'No customers yet',
                      subtitle:
                          'Add a customer above to start recording sales.',
                    )
                  else
                    ..._customers.map((customer) {
                      final name = customer['name'] as String;
                      final phone = customer['phone'] as String?;
                      final owed = _owed[customer['id']] ?? {};
                      final hasDebt = owed.values.any((v) => v > 0.01);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          onTap: () => _openCustomer(customer),
                          child: Row(
                            children: [
                              InitialsAvatar(name: name),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    if (phone != null && phone.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        phone,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.inkMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    hasDebt ? 'Owes' : 'Settled',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: hasDebt
                                          ? AppColors.expense
                                          : AppColors.cashIn,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  DualCurrencyStat(
                                    amounts: {
                                      for (final c in AppCurrency.values)
                                        c: (owed[c] ?? 0).abs(),
                                    },
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: hasDebt
                                          ? AppColors.expense
                                          : AppColors.cashIn,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
