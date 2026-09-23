import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/customer_payments.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'customers_screen.dart';

/// Records a sale of part (or all) of a harvest's remaining stock to one
/// customer, with an optional transportation fee (subtracted from what
/// the customer owes) and an optional upfront payment (often $0 - the
/// rest becomes their outstanding balance, tracked on the Customers
/// screen). A single harvest can have many of these, to the same or
/// different customers, on different dates - see
/// harvest_detail_screen.dart. Any upfront amount feeds Revenue via
/// services/customer_payments.dart.
class AddSaleScreen extends StatefulWidget {
  const AddSaleScreen({super.key, this.preselectedHarvestId});

  /// When opened from a specific harvest's "Add sale" button, that
  /// harvest is pre-selected instead of making the user pick it again.
  final String? preselectedHarvestId;

  @override
  State<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends State<AddSaleScreen> {
  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _harvests = [];
  Map<String, double> _remainingByHarvest = {};

  /// harvestId -> its display code, e.g. "#H3".
  Map<String, String> _codeByHarvest = {};
  List<Map<String, dynamic>> _customers = [];

  String? _selectedHarvestId;
  String? _selectedCustomerId;

  final _kgController = TextEditingController();
  final _priceController = TextEditingController();
  final _transportFeeController = TextEditingController(text: '0.00');
  final _upfrontController = TextEditingController(text: '0.00');
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');
  AppCurrency _selectedCurrency = AppCurrency.usd;

  bool _saving = false;
  String? _errorMessage;

  double get _kg => double.tryParse(_kgController.text) ?? 0;
  double get _pricePerKg => double.tryParse(_priceController.text) ?? 0;
  double get _totalValue => _kg * _pricePerKg;
  double get _transportFee =>
      double.tryParse(_transportFeeController.text) ?? 0;
  double get _customerOwes =>
      (_totalValue - _transportFee).clamp(0, double.infinity);
  double get _upfront => double.tryParse(_upfrontController.text) ?? 0;
  double get _remaining => _remainingByHarvest[_selectedHarvestId] ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
    _kgController.addListener(() => setState(() {}));
    _priceController.addListener(() => setState(() {}));
    _transportFeeController.addListener(() => setState(() {}));
    _upfrontController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _kgController.dispose();
    _priceController.dispose();
    _transportFeeController.dispose();
    _upfrontController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final harvestsData = await supabase
          .from('harvests')
          .select()
          .order('harvest_date', ascending: false);
      final harvests = List<Map<String, dynamic>>.from(harvestsData);

      final salesData = await supabase
          .from('harvest_sales')
          .select('harvest_id, kg_sold');
      final soldByHarvest = <String, double>{};
      for (final s in List<Map<String, dynamic>>.from(salesData)) {
        final id = s['harvest_id'] as String;
        soldByHarvest[id] =
            (soldByHarvest[id] ?? 0) + (s['kg_sold'] as num).toDouble();
      }

      final available = harvests.where((h) {
        final kg = (h['kg_harvested'] as num).toDouble();
        final sold = soldByHarvest[h['id']] ?? 0;
        return (kg - sold) > 0.01;
      }).toList();
      final remaining = {
        for (final h in available)
          h['id'] as String:
              (h['kg_harvested'] as num).toDouble() -
              (soldByHarvest[h['id']] ?? 0),
      };
      final codes = {
        for (final h in harvests) h['id'] as String: '#H${h['harvest_number']}',
      };

      final customersData = await supabase
          .from('customers')
          .select()
          .order('name');

      setState(() {
        _harvests = available;
        _remainingByHarvest = remaining;
        _codeByHarvest = codes;
        _customers = List<Map<String, dynamic>>.from(customersData);
        _selectedHarvestId =
            widget.preselectedHarvestId != null &&
                remaining.containsKey(widget.preselectedHarvestId)
            ? widget.preselectedHarvestId
            : _selectedHarvestId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Could not load harvests: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openAddCustomer() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomersScreen()));
    final customersData = await supabase
        .from('customers')
        .select()
        .order('name');
    if (mounted) {
      setState(
        () => _customers = List<Map<String, dynamic>>.from(customersData),
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

    if (_selectedHarvestId == null) {
      setState(() => _errorMessage = 'Select which harvest this is from.');
      return;
    }
    if (_kg <= 0) {
      setState(() => _errorMessage = 'Enter how many kg you\'re selling.');
      return;
    }
    if (_kg > _remaining + 0.01) {
      setState(
        () => _errorMessage =
            'Only ${_remaining.toStringAsFixed(1)} kg left in this harvest.',
      );
      return;
    }
    if (_pricePerKg <= 0) {
      setState(() => _errorMessage = 'Enter a price per kg.');
      return;
    }
    if (_transportFee < 0) {
      setState(() => _errorMessage = 'Transportation fee can\'t be negative.');
      return;
    }
    if (_transportFee > _totalValue + 0.01) {
      setState(
        () => _errorMessage =
            'Transportation fee can\'t exceed the total value '
            '(${formatMoney(_totalValue, _selectedCurrency)}).',
      );
      return;
    }
    if (_selectedCustomerId == null) {
      setState(() => _errorMessage = 'Select who this was sold to.');
      return;
    }
    if (_upfront < 0) {
      setState(() => _errorMessage = 'Upfront payment can\'t be negative.');
      return;
    }
    if (_upfront > _customerOwes + 0.01) {
      setState(
        () => _errorMessage =
            'Upfront payment can\'t exceed what the customer owes '
            '(${formatMoney(_customerOwes, _selectedCurrency)}).',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final harvestCode = _codeByHarvest[_selectedHarvestId] ?? '';
      final baseNote = _noteController.text.trim();
      final saleNote = baseNote.isEmpty
          ? harvestCode
          : '$baseNote ($harvestCode)';

      final saleResponse = await supabase
          .from('harvest_sales')
          .insert({
            'harvest_id': _selectedHarvestId,
            'customer_id': _selectedCustomerId,
            'kg_sold': _kg,
            'price_per_kg': _pricePerKg,
            'transport_fee': _transportFee,
            'currency': _selectedCurrency.code,
            'sale_date': _dbDateFormat.format(_selectedDate),
            'note': saleNote,
          })
          .select()
          .single();

      if (_upfront > 0) {
        await recordCustomerPayment(
          customerId: _selectedCustomerId!,
          saleId: saleResponse['id'] as String,
          amount: _upfront,
          date: _selectedDate,
          currency: _selectedCurrency,
          note: 'Upfront payment for harvest sale ($harvestCode)',
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
      appBar: AppBar(title: const Text('Sell harvest')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_loadError!)),
            )
          : _harvests.isEmpty
          ? const EmptyState(
              icon: Icons.eco_outlined,
              title: 'Nothing left to sell',
              subtitle:
                  'Every logged harvest is fully sold. Log a new harvest '
                  'first.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const SectionLabel('FROM HARVEST'),
                const SizedBox(height: 8),
                ..._harvests.map((h) {
                  final id = h['id'] as String;
                  final selected = id == _selectedHarvestId;
                  final date = DateTime.parse(h['harvest_date'] as String);
                  final remaining = _remainingByHarvest[id] ?? 0;
                  final code = _codeByHarvest[id] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      accent: selected ? AppColors.brandGreenLight : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () => setState(() => _selectedHarvestId = id),
                      child: Row(
                        children: [
                          const IconBadge(
                            icon: Icons.eco_outlined,
                            color: AppColors.brandGreenLight,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$code · ${_dateFormat.format(date)}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${remaining.toStringAsFixed(1)} kg remaining',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: selected
                                ? AppColors.brandGreenLight
                                : AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),

                const SectionLabel('CURRENCY'),
                const SizedBox(height: 8),
                CurrencyToggle(
                  value: _selectedCurrency,
                  onChanged: (value) =>
                      setState(() => _selectedCurrency = value),
                ),
                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionLabel('KG SOLD'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _kgController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: const InputDecoration(
                              hintText: '0',
                              suffixText: 'kg',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionLabel('PRICE / KG'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  '0${_selectedCurrency.decimalDigits > 0 ? '.00' : ''}',
                              prefixText: '${_selectedCurrency.symbol} ',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const SectionLabel('TRANSPORTATION FEE (OPTIONAL)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _transportFeeController,
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
                  'Deducted from what the customer owes for this sale.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brandGreenLight.withValues(alpha: 0.13),
                        AppColors.brandGreen.withValues(alpha: 0.07),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppStyles.radiusField),
                    border: Border.all(
                      color: AppColors.brandGreen.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    children: [
                      _summaryRow(
                        'Total value',
                        formatMoney(_totalValue, _selectedCurrency),
                      ),
                      if (_transportFee > 0) ...[
                        const SizedBox(height: 6),
                        _summaryRow(
                          'Transportation fee',
                          '− ${formatMoney(_transportFee, _selectedCurrency)}',
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1),
                        ),
                        _summaryRow(
                          'Customer owes',
                          formatMoney(_customerOwes, _selectedCurrency),
                          emphasize: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SectionLabel('SOLD TO'),
                    InkWell(
                      onTap: _openAddCustomer,
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
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
                              'Add customer',
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
                  initialValue: _selectedCustomerId,
                  items: _customers
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text(c['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedCustomerId = value),
                  hint: Text(
                    'Select customer',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
                const SizedBox(height: 20),

                const SectionLabel('UPFRONT PAYMENT'),
                const SizedBox(height: 8),
                TextField(
                  controller: _upfrontController,
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
                  _upfront >= _customerOwes && _customerOwes > 0
                      ? 'Paid in full - nothing added to their balance.'
                      : 'Remaining ${formatMoney((_customerOwes - _upfront).clamp(0, double.infinity), _selectedCurrency)} will be added to their balance.',
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
                          const Icon(
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
                        : const Text('Save sale'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 14 : 13.5,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: AppColors.brandGreenDeep,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 18 : 14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.brandGreenDeep,
          ),
        ),
      ],
    );
  }
}
