import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import 'expense_categories_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key, this.existingTransaction});

  /// When set, the form is pre-filled from this transaction (including its
  /// `transaction_items`) and saving replaces it: a new transaction is
  /// inserted and the old one is deleted, rather than updating in place.
  final Map<String, dynamic>? existingTransaction;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _LineItem {
  _LineItem({this.pendingCategoryName, String amount = ''})
      : amountController = TextEditingController(text: amount);

  /// The invoice's category id, selected from `expense_categories`.
  String? categoryId;

  /// Category name carried over from an existing transaction until the
  /// category list loads and can be matched to an id.
  String? pendingCategoryName;

  final TextEditingController amountController;
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  static const _types = ['expense', 'payroll', 'loan', 'advance'];

  static const _borderColor = Color(0xFFE5E5E5);
  static const _labelColor = Color(0xFF6B6B6B);
  static const _splitBg = Color(0xFFD6E8F8);
  static const _splitFg = Color(0xFF2B6CB0);
  static const _allocatedOk = Color(0xFF2F6B3A);

  String _selectedType = 'expense';

  final _totalController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');

  bool _splitEnabled = false;
  List<_LineItem> _items = [_LineItem()];

  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _categories = [];
  String? _selectedPartnerId;
  String? _selectedStaffId;
  String? _selectedCategoryId;
  String? _pendingCategoryName;

  bool _isRepayment = false;

  double _staffBaseSalary = 0;
  double _staffOwed = 0;
  bool _loadingStaffFinancials = false;
  final _repayAmountController = TextEditingController(text: '0.00');
  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  bool _saving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existingTransaction != null;

  bool get _needsPartner => _selectedType == 'loan';
  bool get _needsStaff => _selectedType == 'payroll' || _selectedType == 'advance';
  bool get _supportsSplit => _selectedType == 'expense';

  /// The type actually saved to the database - 'loan' flips to
  /// 'loan_repayment' when the repayment toggle is on.
  String get _effectiveType =>
      (_selectedType == 'loan' && _isRepayment) ? 'loan_repayment' : _selectedType;

  double get _repayAmount => double.tryParse(_repayAmountController.text) ?? 0;
  double get _payrollNetAmount =>
      (_staffBaseSalary - _repayAmount).clamp(0, double.infinity);

  double get _totalAmount => double.tryParse(_totalController.text) ?? 0;
  double get _allocatedAmount =>
      _items.fold(0, (sum, item) => sum + (double.tryParse(item.amountController.text) ?? 0));

  bool get _allocationMatches => (_allocatedAmount - _totalAmount).abs() < 0.01 && _totalAmount > 0;

  @override
  void initState() {
    super.initState();
    _loadPeople();
    _loadCategories();

    final existing = widget.existingTransaction;
    if (existing != null) {
      _selectedType = existing['type'] as String;
      _selectedDate = DateTime.parse(existing['transaction_date'] as String);
      _totalController.text = (existing['amount'] as num).toDouble().toStringAsFixed(2);
      _noteController.text = existing['note'] as String? ?? '';
      _selectedPartnerId = existing['related_partner_id'] as String?;
      _selectedStaffId = existing['related_staff_id'] as String?;

      final items = List<Map<String, dynamic>>.from(
        existing['transaction_items'] ?? [],
      );
      if (items.length > 1) {
        _splitEnabled = true;
        for (final item in _items) {
          item.amountController.dispose();
        }
        _items = items
            .map((i) => _LineItem(
                  pendingCategoryName: i['category'] as String?,
                  amount: (i['amount'] as num).toDouble().toStringAsFixed(2),
                ))
            .toList();
      } else if (items.isNotEmpty) {
        _pendingCategoryName = items.first['category'] as String?;
      }
    }
  }

  @override
  void dispose() {
    _totalController.dispose();
    _noteController.dispose();
    _repayAmountController.dispose();
    for (final item in _items) {
      item.amountController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPeople() async {
    final partners = await supabase.from('partners').select();
    final staff = await supabase.from('staff').select();
    setState(() {
      _partners = List<Map<String, dynamic>>.from(partners);
      _staff = List<Map<String, dynamic>>.from(staff);
    });
  }

  Future<void> _loadStaffFinancials(String staffId) async {
    setState(() => _loadingStaffFinancials = true);

    final staff = _staff.firstWhere((s) => s['id'] == staffId);
    final baseSalary = (staff['base_salary'] as num).toDouble();

    final advances = await supabase
        .from('transactions')
        .select('amount')
        .eq('type', 'advance')
        .eq('related_staff_id', staffId);
    final deductions = await supabase
        .from('transactions')
        .select('amount')
        .eq('type', 'advance_deduction')
        .eq('related_staff_id', staffId);

    double advanceTotal = 0;
    for (final a in advances) {
      advanceTotal += (a['amount'] as num).toDouble();
    }
    double deductionTotal = 0;
    for (final d in deductions) {
      deductionTotal += (d['amount'] as num).toDouble();
    }

    if (!mounted) return;
    setState(() {
      _staffBaseSalary = baseSalary;
      _staffOwed = advanceTotal - deductionTotal;
      _loadingStaffFinancials = false;
      _syncPayrollAmount();
    });
  }

  void _syncPayrollAmount() {
    _totalController.text = _payrollNetAmount.toStringAsFixed(2);
  }

  Future<void> _loadCategories() async {
    final categories = await supabase
        .from('expense_categories')
        .select()
        .order('name');
    setState(() {
      _categories = List<Map<String, dynamic>>.from(categories);

      String? idForName(String? name) {
        if (name == null) return null;
        for (final c in _categories) {
          if (c['name'] == name) return c['id'] as String;
        }
        return null;
      }

      if (_pendingCategoryName != null) {
        _selectedCategoryId = idForName(_pendingCategoryName);
        _pendingCategoryName = null;
      }
      for (final item in _items) {
        if (item.pendingCategoryName != null) {
          item.categoryId = idForName(item.pendingCategoryName);
          item.pendingCategoryName = null;
        }
      }
    });
  }

  Future<void> _openManageCategories() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExpenseCategoriesScreen()),
    );
    _loadCategories();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('en', 'SA'),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    setState(() => _errorMessage = null);

    final isPayroll = _selectedType == 'payroll';
    if (isPayroll ? _totalAmount < 0 : _totalAmount <= 0) {
      setState(() => _errorMessage = 'Enter a total amount greater than zero.');
      return;
    }
    if (_needsPartner && _selectedPartnerId == null) {
      setState(() => _errorMessage = 'Select a partner for this loan.');
      return;
    }
    if (_needsStaff && _selectedStaffId == null) {
      setState(() => _errorMessage = 'Select a staff member.');
      return;
    }
    if (_splitEnabled && (_allocatedAmount - _totalAmount).abs() > 0.01) {
      setState(() => _errorMessage = 'Invoice amounts must add up to the total.');
      return;
    }
    if (_selectedType == 'expense' && !_splitEnabled && _selectedCategoryId == null) {
      setState(() => _errorMessage = 'Select a category.');
      return;
    }
    if (_splitEnabled && _items.any((item) => item.categoryId == null)) {
      setState(() => _errorMessage = 'Select a category for every invoice.');
      return;
    }
    if (isPayroll && _repayAmount > _staffOwed + 0.01) {
      setState(() => _errorMessage =
          'Repay amount can\'t exceed the amount owed (${_currency.format(_staffOwed)}).');
      return;
    }
    if (isPayroll && _repayAmount > _staffBaseSalary + 0.01) {
      setState(() => _errorMessage = 'Repay amount can\'t exceed the base salary.');
      return;
    }

    setState(() => _saving = true);

    try {
      final txnResponse = await supabase.from('transactions').insert({
        'type': _effectiveType,
        'amount': _totalAmount,
        'transaction_date': _dbDateFormat.format(_selectedDate),
        'related_partner_id': _needsPartner ? _selectedPartnerId : null,
        'related_staff_id': _needsStaff ? _selectedStaffId : null,
        'note': _noteController.text.trim(),
      }).select().single();

      final transactionId = txnResponse['id'];

      if (_splitEnabled) {
        final itemRows = _items
            .map((item) => {
                  'transaction_id': transactionId,
                  'category': _categoryName(item.categoryId),
                  'amount': double.tryParse(item.amountController.text) ?? 0,
                })
            .toList();
        await supabase.from('transaction_items').insert(itemRows);
      } else {
        await supabase.from('transaction_items').insert({
          'transaction_id': transactionId,
          'category': _selectedType == 'expense'
              ? _categoryName(_selectedCategoryId)
              : _effectiveType,
          'amount': _totalAmount,
        });
      }

      if (isPayroll && _repayAmount > 0) {
        final deductionResponse = await supabase.from('transactions').insert({
          'type': 'advance_deduction',
          'amount': _repayAmount,
          'transaction_date': _dbDateFormat.format(_selectedDate),
          'related_staff_id': _selectedStaffId,
          'note': 'Advance deduction for payroll',
        }).select().single();

        await supabase.from('transaction_items').insert({
          'transaction_id': deductionResponse['id'],
          'category': 'advance_deduction',
          'amount': _repayAmount,
        });
      }

      if (_isEditing) {
        await supabase
            .from('transactions')
            .delete()
            .eq('id', widget.existingTransaction!['id']);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addItem() => setState(() => _items.add(_LineItem()));

  void _removeItem(int index) {
    final item = _items.removeAt(index);
    item.amountController.dispose();
    setState(() {});
  }

  String _categoryName(String? categoryId) {
    for (final c in _categories) {
      if (c['id'] == categoryId) return c['name'] as String;
    }
    return '';
  }

  IconData _iconForCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('fuel') || lower.contains('gas')) return Icons.water_drop_outlined;
    if (lower.contains('water')) return Icons.local_bar_outlined;
    if (lower.contains('food') || lower.contains('meal')) return Icons.restaurant_outlined;
    if (lower.contains('seed') || lower.contains('feed')) return Icons.grass_outlined;
    if (lower.contains('tool') || lower.contains('equip')) return Icons.build_outlined;
    if (lower.contains('labor') || lower.contains('wage')) return Icons.person_outline;
    return Icons.category_outlined;
  }

  InputDecoration _fieldDecoration({String? hint, bool large = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.grey.shade400,
        fontSize: large ? 22 : 14,
        fontWeight: large ? FontWeight.w600 : FontWeight.w400,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: large ? 18 : 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBBBBBB)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit transaction' : 'New transaction',
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 18),
        ),
        backgroundColor: const Color(0xFFF7F7F5),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _typeGrid(),
          const SizedBox(height: 24),

          _sectionLabel('Date'),
          const SizedBox(height: 6),
          _dateField(),
          const SizedBox(height: 20),

          if (_needsPartner) ...[
            _sectionLabel('Partner'),
            const SizedBox(height: 6),
            _dropdownField<String>(
              value: _selectedPartnerId,
              hint: 'Select partner',
              items: _partners
                  .map((p) => DropdownMenuItem<String>(
                        value: p['id'] as String,
                        child: Text(p['name'] as String),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _selectedPartnerId = value),
            ),
            const SizedBox(height: 16),
            _repayToggle(),
            const SizedBox(height: 20),
          ],

          if (_needsStaff) ...[
            _sectionLabel('Staff member'),
            const SizedBox(height: 6),
            _dropdownField<String>(
              value: _selectedStaffId,
              hint: 'Select staff member',
              items: _staff
                  .map((s) => DropdownMenuItem<String>(
                        value: s['id'] as String,
                        child: Text(s['name'] as String),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedStaffId = value);
                if (value != null && _selectedType == 'payroll') {
                  _loadStaffFinancials(value);
                }
              },
            ),
            const SizedBox(height: 20),
          ],

          if (_selectedType == 'payroll' && _selectedStaffId != null) ...[
            _payrollBreakdown(),
            const SizedBox(height: 20),
          ],

          if (_selectedType == 'expense' && !_splitEnabled) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel('Category'),
                _manageCategoriesLink(),
              ],
            ),
            const SizedBox(height: 6),
            _dropdownField<String>(
              value: _selectedCategoryId,
              hint: 'Select category',
              items: _categories
                  .map((c) => DropdownMenuItem<String>(
                        value: c['id'] as String,
                        child: Text(c['name'] as String),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _selectedCategoryId = value),
            ),
            const SizedBox(height: 20),
          ],

          _sectionLabel(
            _selectedType == 'payroll' ? 'Amount he will receive' : 'Total amount',
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _totalController,
            enabled: _selectedType != 'payroll',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: _fieldDecoration(hint: '\$0.00', large: true).copyWith(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          if (_supportsSplit) ...[
            _splitToggle(),
            const SizedBox(height: 16),
          ],

          if (_splitEnabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Category', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      const SizedBox(width: 130),
                      Text('Amount', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                  _manageCategoriesLink(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _categoryRow(index, item),
              );
            }),
            _addCategoryButton(),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _borderColor),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Allocated', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                Text(
                  '\$${_allocatedAmount.toStringAsFixed(2)} of \$${_totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _allocationMatches ? _allocatedOk : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          _sectionLabel('Note (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            decoration: _fieldDecoration(hint: 'Add a note'),
          ),
          const SizedBox(height: 24),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _isEditing ? 'Save changes' : 'Save transaction',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, color: _labelColor));
  }

  Widget _dateField() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dateFormat.format(_selectedDate),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
              Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _typeButton(_types[0])),
            const SizedBox(width: 10),
            Expanded(child: _typeButton(_types[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _typeButton(_types[2])),
            const SizedBox(width: 10),
            Expanded(child: _typeButton(_types[3])),
          ],
        ),
      ],
    );
  }

  Widget _typeButton(String type) {
    final selected = type == _selectedType;
    final label = type[0].toUpperCase() + type.substring(1);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedType = type;
            if (!_supportsSplit) _splitEnabled = false;
            if (type != 'loan') _isRepayment = false;
          });
          if (type == 'payroll' && _selectedStaffId != null) {
            _loadStaffFinancials(_selectedStaffId!);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF222222) : _borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? Colors.black : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdownField<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: _fieldDecoration(hint: hint),
      hint: Text(hint, style: TextStyle(color: Colors.grey.shade400)),
    );
  }

  Widget _manageCategoriesLink() {
    return InkWell(
      onTap: _openManageCategories,
      child: Text(
        'Manage categories',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _repayToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _splitBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'This is a repayment',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _splitFg,
              ),
            ),
          ),
          Switch.adaptive(
            value: _isRepayment,
            activeTrackColor: _splitFg,
            activeThumbColor: Colors.white,
            onChanged: (value) => setState(() => _isRepayment = value),
          ),
        ],
      ),
    );
  }

  Widget _payrollInfoField(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF444444),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payrollBreakdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _payrollInfoField(
              'Base salary',
              _loadingStaffFinancials ? '…' : _currency.format(_staffBaseSalary),
            ),
            const SizedBox(width: 10),
            _payrollInfoField(
              'Owed (advance)',
              _loadingStaffFinancials ? '…' : _currency.format(_staffOwed),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel('Repay amount (deduct from this salary)'),
        const SizedBox(height: 6),
        TextField(
          controller: _repayAmountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _fieldDecoration(hint: '\$0.00').copyWith(prefixText: '\$ '),
          onChanged: (_) => setState(_syncPayrollAmount),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF5EA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'He will receive',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              Text(
                _currency.format(_payrollNetAmount),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _splitToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _splitBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Multiple invoices',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _splitFg,
              ),
            ),
          ),
          Switch.adaptive(
            value: _splitEnabled,
            activeTrackColor: _splitFg,
            activeThumbColor: Colors.white,
            onChanged: (value) => setState(() => _splitEnabled = value),
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(int index, _LineItem item) {
    final categoryName = _categoryName(item.categoryId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Icon(_iconForCategory(categoryName), size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: item.categoryId,
              items: _categories
                  .map((c) => DropdownMenuItem<String>(
                        value: c['id'] as String,
                        child: Text(c['name'] as String),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => item.categoryId = value),
              decoration: const InputDecoration(
                hintText: 'Category',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              hint: Text('Category', style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black),
            ),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: item.amountController,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '\$0.00',
                prefixText: '\$ ',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
            visualDensity: VisualDensity.compact,
            onPressed: _items.length > 1 ? () => _removeItem(index) : null,
          ),
        ],
      ),
    );
  }

  Widget _addCategoryButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _addItem,
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: Colors.grey.shade300,
            radius: 12,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: Text(
              '+ Add invoice',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
