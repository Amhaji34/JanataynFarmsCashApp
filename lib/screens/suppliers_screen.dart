import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'add_purchase_screen.dart';
import 'supplier_detail_screen.dart';

/// Lists suppliers with what's currently owed to each one (calculated
/// from supplier_purchases + supplier_payments), plus an add-new form -
/// same combined list+add pattern as customers_screen.dart /
/// partners_screen.dart, just money flowing the other direction.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _suppliers = [];
  Map<String, Map<AppCurrency, double>> _owed = {};
  String? _role;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  bool _adding = false;
  String? _addError;

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
      final suppliersData = await supabase
          .from('suppliers')
          .select()
          .order('name');
      final suppliers = List<Map<String, dynamic>>.from(suppliersData);

      final purchasesData = await supabase
          .from('supplier_purchases')
          .select('supplier_id, amount, currency');
      final purchases = List<Map<String, dynamic>>.from(purchasesData);

      final paymentsData = await supabase
          .from('supplier_payments')
          .select('supplier_id, amount, currency');
      final payments = List<Map<String, dynamic>>.from(paymentsData);

      final owed = <String, Map<AppCurrency, double>>{};
      for (final supplier in suppliers) {
        final id = supplier['id'] as String;
        final bought = {for (final c in AppCurrency.values) c: 0.0};
        for (final p in purchases) {
          if (p['supplier_id'] != id) continue;
          final currency = AppCurrency.fromCode(p['currency'] as String?);
          bought[currency] =
              (bought[currency] ?? 0) + (p['amount'] as num).toDouble();
        }
        final paid = {for (final c in AppCurrency.values) c: 0.0};
        for (final p in payments) {
          if (p['supplier_id'] != id) continue;
          final currency = AppCurrency.fromCode(p['currency'] as String?);
          paid[currency] =
              (paid[currency] ?? 0) + (p['amount'] as num).toDouble();
        }
        owed[id] = {
          for (final c in AppCurrency.values)
            c: (bought[c] ?? 0) - (paid[c] ?? 0),
        };
      }

      setState(() {
        _suppliers = suppliers;
        _owed = owed;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load suppliers: $e';
        _loading = false;
      });
    }
  }

  Future<void> _addSupplier() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      await supabase.from('suppliers').insert({
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
      setState(() => _addError = 'Could not add supplier: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openAddPurchase() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddPurchaseScreen()));
    if (result == true) _load();
  }

  Future<void> _openSupplier(Map<String, dynamic> supplier) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierDetailScreen(
          supplierId: supplier['id'] as String,
          supplierName: supplier['name'] as String,
          supplierPhone: supplier['phone'] as String?,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      floatingActionButton: _role == 'admin'
          ? FloatingActionButton.extended(
              onPressed: _openAddPurchase,
              icon: const Icon(Icons.shopping_bag_outlined, size: 20),
              label: const Text(
                'Purchase',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('ADD A SUPPLIER'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'Supplier name',
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
                          decoration: InputDecoration(
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
                            onPressed: _adding ? null : _addSupplier,
                            child: _adding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Add supplier'),
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
                  if (_suppliers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: SectionLabel(
                        'ALL SUPPLIERS',
                        trailing: Text(
                          '${_suppliers.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  if (_suppliers.isEmpty)
                    const EmptyState(
                      icon: Icons.local_shipping_outlined,
                      title: 'No suppliers yet',
                      subtitle:
                          'Add a supplier above to start recording purchases.',
                    )
                  else
                    ..._suppliers.map((supplier) {
                      final name = supplier['name'] as String;
                      final phone = supplier['phone'] as String?;
                      final owed = _owed[supplier['id']] ?? {};
                      final hasDebt = owed.values.any((v) => v > 0.01);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          onTap: () => _openSupplier(supplier),
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
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    if (phone != null && phone.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        phone,
                                        style: TextStyle(
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
                                    hasDebt ? 'You owe' : 'Settled',
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
