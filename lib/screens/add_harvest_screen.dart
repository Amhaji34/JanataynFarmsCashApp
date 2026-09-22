import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/customer_payments.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'customers_screen.dart';

/// Logs one harvest, which doubles as its sale record: how much was
/// harvested, the price per kg, who bought it, and how much they paid
/// upfront (often $0 - the rest becomes their outstanding balance,
/// tracked on the Customers screen). Any upfront amount feeds Revenue via
/// services/customer_payments.dart.
class AddHarvestScreen extends StatefulWidget {
  const AddHarvestScreen({super.key});

  @override
  State<AddHarvestScreen> createState() => _AddHarvestScreenState();
}

class _AddHarvestScreenState extends State<AddHarvestScreen> {
  bool _loadingCustomers = true;
  String? _loadError;
  List<Map<String, dynamic>> _customers = [];
  String? _selectedCustomerId;

  final _kgController = TextEditingController();
  final _priceController = TextEditingController();
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
  double get _upfront => double.tryParse(_upfrontController.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _kgController.addListener(() => setState(() {}));
    _priceController.addListener(() => setState(() {}));
    _upfrontController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _kgController.dispose();
    _priceController.dispose();
    _upfrontController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _loadingCustomers = true);
    try {
      final data = await supabase.from('customers').select().order('name');
      setState(() {
        _customers = List<Map<String, dynamic>>.from(data);
        _loadingCustomers = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Could not load customers: $e';
        _loadingCustomers = false;
      });
    }
  }

  Future<void> _openAddCustomer() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomersScreen()));
    _loadCustomers();
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

    if (_kg <= 0) {
      setState(() => _errorMessage = 'Enter how many kg were harvested.');
      return;
    }
    if (_pricePerKg <= 0) {
      setState(() => _errorMessage = 'Enter a price per kg.');
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
    if (_upfront > _totalValue + 0.01) {
      setState(
        () => _errorMessage =
            'Upfront payment can\'t exceed the total value '
            '(${formatMoney(_totalValue, _selectedCurrency)}).',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final harvestResponse = await supabase
          .from('harvests')
          .insert({
            'harvest_date': _dbDateFormat.format(_selectedDate),
            'kg_harvested': _kg,
            'price_per_kg': _pricePerKg,
            'customer_id': _selectedCustomerId,
            'note': _noteController.text.trim(),
            'currency': _selectedCurrency.code,
          })
          .select()
          .single();

      if (_upfront > 0) {
        await recordCustomerPayment(
          customerId: _selectedCustomerId!,
          harvestId: harvestResponse['id'] as String,
          amount: _upfront,
          date: _selectedDate,
          currency: _selectedCurrency,
          note: 'Upfront payment for harvest sale',
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
      appBar: AppBar(title: const Text('Add harvest')),
      body: _loadingCustomers
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_loadError!)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
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
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: AppColors.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

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
                          const SectionLabel('KG HARVESTED'),
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
                  child: Row(
                    children: [
                      const Icon(
                        Icons.eco_outlined,
                        size: 18,
                        color: AppColors.brandGreen,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Total value',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandGreenDeep,
                          ),
                        ),
                      ),
                      Text(
                        formatMoney(_totalValue, _selectedCurrency),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: AppColors.brandGreenDeep,
                        ),
                      ),
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
                  _upfront >= _totalValue && _totalValue > 0
                      ? 'Paid in full - nothing added to their balance.'
                      : 'Remaining ${formatMoney((_totalValue - _upfront).clamp(0, double.infinity), _selectedCurrency)} will be added to their balance.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 20),

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
                        : const Text('Save harvest'),
                  ),
                ),
              ],
            ),
    );
  }
}
