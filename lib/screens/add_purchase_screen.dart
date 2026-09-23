import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/supplier_payments.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'suppliers_screen.dart';

/// Records something bought from a supplier - an item, its total cost,
/// and how much was paid right now (often $0 or partial - the rest
/// becomes that supplier's outstanding balance, tracked on the
/// Suppliers screen). Any amount paid now is booked immediately as a
/// real expense against Petty Cash via services/supplier_payments.dart.
class AddPurchaseScreen extends StatefulWidget {
  const AddPurchaseScreen({super.key, this.preselectedSupplierId});

  /// When opened from a specific supplier's "Add purchase" button, that
  /// supplier is pre-selected instead of making the user pick it again.
  final String? preselectedSupplierId;

  @override
  State<AddPurchaseScreen> createState() => _AddPurchaseScreenState();
}

class _AddPurchaseScreenState extends State<AddPurchaseScreen> {
  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _suppliers = [];
  String? _selectedSupplierId;

  final _itemController = TextEditingController();
  final _amountController = TextEditingController();
  final _paidNowController = TextEditingController(text: '0.00');
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');
  AppCurrency _selectedCurrency = AppCurrency.usd;

  bool _saving = false;
  String? _errorMessage;

  double get _amount => double.tryParse(_amountController.text) ?? 0;
  double get _paidNow => double.tryParse(_paidNowController.text) ?? 0;
  double get _remainingOwed => (_amount - _paidNow).clamp(0.0, double.infinity);

  @override
  void initState() {
    super.initState();
    _load();
    _amountController.addListener(() => setState(() {}));
    _paidNowController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _itemController.dispose();
    _amountController.dispose();
    _paidNowController.dispose();
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

      setState(() {
        _suppliers = List<Map<String, dynamic>>.from(suppliersData);
        _selectedSupplierId =
            widget.preselectedSupplierId != null &&
                _suppliers.any((s) => s['id'] == widget.preselectedSupplierId)
            ? widget.preselectedSupplierId
            : _selectedSupplierId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Could not load suppliers: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openAddSupplier() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SuppliersScreen()));
    final suppliersData = await supabase
        .from('suppliers')
        .select()
        .order('name');
    if (mounted) {
      setState(
        () => _suppliers = List<Map<String, dynamic>>.from(suppliersData),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    setState(() => _errorMessage = null);

    if (_selectedSupplierId == null) {
      setState(() => _errorMessage = 'Select who this was bought from.');
      return;
    }
    if (_itemController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Describe what you bought.');
      return;
    }
    if (_amount <= 0) {
      setState(() => _errorMessage = 'Enter the total cost.');
      return;
    }
    if (_paidNow < 0) {
      setState(() => _errorMessage = 'Amount paid can\'t be negative.');
      return;
    }
    if (_paidNow > _amount + 0.01) {
      setState(
        () => _errorMessage =
            'Amount paid can\'t exceed the total cost '
            '(${formatMoney(_amount, _selectedCurrency)}).',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final purchaseResponse = await supabase
          .from('supplier_purchases')
          .insert({
            'supplier_id': _selectedSupplierId,
            'item': _itemController.text.trim(),
            'amount': _amount,
            'currency': _selectedCurrency.code,
            'purchase_date': _dbDateFormat.format(_selectedDate),
            'note': _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          })
          .select()
          .single();

      if (_paidNow > 0) {
        await recordSupplierPayment(
          supplierId: _selectedSupplierId!,
          purchaseId: purchaseResponse['id'] as String,
          amount: _paidNow,
          date: _selectedDate,
          currency: _selectedCurrency,
          note: 'Paid for ${_itemController.text.trim()}',
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add purchase')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_loadError!)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SectionLabel('BOUGHT FROM'),
                    InkWell(
                      onTap: _openAddSupplier,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_add_alt_outlined,
                              size: 13,
                              color: AppColors.brandGreen,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Add supplier',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSupplierId,
                  items: _suppliers
                      .map(
                        (s) => DropdownMenuItem<String>(
                          value: s['id'] as String,
                          child: Text(s['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedSupplierId = value),
                  hint: Text(
                    'Select supplier',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
                const SizedBox(height: 20),

                const SectionLabel('WHAT DID YOU BUY'),
                const SizedBox(height: 8),
                TextField(
                  controller: _itemController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Fertilizer, seeds, tools',
                  ),
                ),
                const SizedBox(height: 20),

                const SectionLabel('CURRENCY'),
                const SizedBox(height: 8),
                CurrencyToggle(
                  value: _selectedCurrency,
                  onChanged: (value) =>
                      setState(() => _selectedCurrency = value),
                ),
                const SizedBox(height: 18),

                const SectionLabel('TOTAL COST'),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: '${_selectedCurrency.symbol}0',
                    prefixText: '${_selectedCurrency.symbol} ',
                    prefixStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const SectionLabel('PAID NOW'),
                const SizedBox(height: 8),
                TextField(
                  controller: _paidNowController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: '${_selectedCurrency.symbol}0',
                    prefixText: '${_selectedCurrency.symbol} ',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _paidNow >= _amount && _amount > 0
                      ? 'Paid in full - nothing added to their balance.'
                      : 'Remaining ${formatMoney(_remainingOwed, _selectedCurrency)} will be added to what you owe this supplier.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 20),

                const SectionLabel('DATE'),
                const SizedBox(height: 8),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppStyles.radiusField),
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(AppStyles.radiusField),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppStyles.radiusField,
                        ),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 17,
                            color: AppColors.brandGreen,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _dateFormat.format(_selectedDate),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const SectionLabel('NOTE (OPTIONAL)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(hintText: 'Add a note'),
                ),
                const SizedBox(height: 24),

                if (_errorMessage != null) ...[
                  ErrorNote(_errorMessage!),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save purchase'),
                  ),
                ),
              ],
            ),
    );
  }
}
