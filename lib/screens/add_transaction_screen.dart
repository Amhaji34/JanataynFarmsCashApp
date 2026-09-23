import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
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
  _LineItem({this.pendingCategoryName, String amount = '', String note = ''})
    : amountController = TextEditingController(text: amount),
      noteController = TextEditingController(text: note);

  /// The invoice's category id, selected from `expense_categories`.
  String? categoryId;

  /// Category name carried over from an existing transaction until the
  /// category list loads and can be matched to an id.
  String? pendingCategoryName;

  final TextEditingController amountController;
  final TextEditingController noteController;
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  static const _types = ['expense', 'loan', 'advance'];

  static const _allocatedOk = AppColors.cashIn;

  String _selectedType = 'expense';

  final _totalController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');

  AppCurrency _selectedCurrency = AppCurrency.usd;

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

  bool _saving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existingTransaction != null;

  bool get _needsPartner => _selectedType == 'loan';
  bool get _needsStaff => _selectedType == 'advance';
  bool get _supportsSplit => _selectedType == 'expense';

  /// The type actually saved to the database - 'loan' flips to
  /// 'loan_repayment' when the repayment toggle is on.
  String get _effectiveType => (_selectedType == 'loan' && _isRepayment)
      ? 'loan_repayment'
      : _selectedType;

  double get _totalAmount => double.tryParse(_totalController.text) ?? 0;
  double get _allocatedAmount => _items.fold(
    0,
    (sum, item) => sum + (double.tryParse(item.amountController.text) ?? 0),
  );

  bool get _allocationMatches =>
      (_allocatedAmount - _totalAmount).abs() < 0.01 && _totalAmount > 0;

  @override
  void initState() {
    super.initState();
    _loadPeople();
    _loadCategories();

    final existing = widget.existingTransaction;
    if (existing != null) {
      _selectedType = existing['type'] as String;
      _selectedDate = DateTime.parse(existing['transaction_date'] as String);
      _totalController.text = (existing['amount'] as num)
          .toDouble()
          .toStringAsFixed(2);
      _noteController.text = existing['note'] as String? ?? '';
      _selectedPartnerId = existing['related_partner_id'] as String?;
      _selectedStaffId = existing['related_staff_id'] as String?;
      _selectedCurrency = AppCurrency.fromCode(existing['currency'] as String?);

      final items = List<Map<String, dynamic>>.from(
        existing['transaction_items'] ?? [],
      );
      if (items.length > 1) {
        _splitEnabled = true;
        for (final item in _items) {
          item.amountController.dispose();
          item.noteController.dispose();
        }
        _items = items
            .map(
              (i) => _LineItem(
                pendingCategoryName: i['category'] as String?,
                amount: (i['amount'] as num).toDouble().toStringAsFixed(2),
                note: i['note'] as String? ?? '',
              ),
            )
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
    for (final item in _items) {
      item.amountController.dispose();
      item.noteController.dispose();
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExpenseCategoriesScreen()));
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

    if (_totalAmount <= 0) {
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
      setState(
        () => _errorMessage = 'Invoice amounts must add up to the total.',
      );
      return;
    }
    if (_selectedType == 'expense' &&
        !_splitEnabled &&
        _selectedCategoryId == null) {
      setState(() => _errorMessage = 'Select a category.');
      return;
    }
    if (_splitEnabled && _items.any((item) => item.categoryId == null)) {
      setState(() => _errorMessage = 'Select a category for every invoice.');
      return;
    }

    setState(() => _saving = true);

    try {
      final txnResponse = await supabase
          .from('transactions')
          .insert({
            'type': _effectiveType,
            'amount': _totalAmount,
            'transaction_date': _dbDateFormat.format(_selectedDate),
            'related_partner_id': _needsPartner ? _selectedPartnerId : null,
            'related_staff_id': _needsStaff ? _selectedStaffId : null,
            'note': _noteController.text.trim(),
            'currency': _selectedCurrency.code,
          })
          .select()
          .single();

      final transactionId = txnResponse['id'];

      if (_splitEnabled) {
        final itemRows = _items
            .map(
              (item) => {
                'transaction_id': transactionId,
                'category': _categoryName(item.categoryId),
                'amount': double.tryParse(item.amountController.text) ?? 0,
                'note': item.noteController.text.trim().isEmpty
                    ? null
                    : item.noteController.text.trim(),
              },
            )
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
    item.noteController.dispose();
    setState(() {});
  }

  String _categoryName(String? categoryId) {
    for (final c in _categories) {
      if (c['id'] == categoryId) return c['name'] as String;
    }
    return '';
  }

  IconData _iconForCategory(String name) => AppIcons.forCategory(name);

  /// Icon shown on each type button in the selector.
  IconData _iconForType(String type) {
    switch (type) {
      case 'expense':
        return Icons.receipt_long_outlined;
      case 'loan':
        return Icons.pan_tool_outlined;
      case 'advance':
        return Icons.pan_tool_alt_outlined;
      default:
        return Icons.more_horiz;
    }
  }

  InputDecoration _fieldDecoration({String? hint, bool large = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.inkMuted.withValues(alpha: 0.8),
        fontSize: large ? 22 : 14,
        fontWeight: large ? FontWeight.w600 : FontWeight.w400,
      ),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: large ? 18 : 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        borderSide: const BorderSide(
          color: AppColors.brandGreenLight,
          width: 1.6,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit transaction' : 'New transaction'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _sectionLabel('Type'),
          const SizedBox(height: 8),
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
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p['id'] as String,
                      child: Text(p['name'] as String),
                    ),
                  )
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
                  .map(
                    (s) => DropdownMenuItem<String>(
                      value: s['id'] as String,
                      child: Text(s['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedStaffId = value),
            ),
            const SizedBox(height: 20),
          ],

          if (_selectedType == 'expense' && !_splitEnabled) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_sectionLabel('Category'), _manageCategoriesLink()],
            ),
            const SizedBox(height: 6),
            _dropdownField<String>(
              value: _selectedCategoryId,
              hint: 'Select category',
              items: _categories
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c['id'] as String,
                      child: Text(c['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedCategoryId = value),
            ),
            const SizedBox(height: 20),
          ],

          _sectionLabel('Currency'),
          const SizedBox(height: 8),
          CurrencyToggle(
            value: _selectedCurrency,
            onChanged: (value) => setState(() => _selectedCurrency = value),
          ),
          const SizedBox(height: 20),

          _sectionLabel('Total amount'),
          const SizedBox(height: 6),
          TextField(
            controller: _totalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration:
                _fieldDecoration(
                  hint: '${_selectedCurrency.symbol}0',
                  large: true,
                ).copyWith(
                  prefixText: '${_selectedCurrency.symbol} ',
                  prefixStyle: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          if (_supportsSplit) ...[_splitToggle(), const SizedBox(height: 16)],

          if (_splitEnabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 130),
                      Text(
                        'Amount',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: (_allocationMatches ? _allocatedOk : Colors.orange)
                    .withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_allocationMatches ? _allocatedOk : Colors.orange)
                      .withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _allocationMatches
                            ? Icons.check_circle_outline
                            : Icons.pending_outlined,
                        size: 17,
                        color: _allocationMatches
                            ? _allocatedOk
                            : Colors.orange.shade800,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Allocated',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${formatMoney(_allocatedAmount, _selectedCurrency)} of '
                    '${formatMoney(_totalAmount, _selectedCurrency)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _allocationMatches
                          ? _allocatedOk
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
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
                  : Text(
                      _isEditing ? 'Save changes' : 'Save transaction',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => SectionLabel(text.toUpperCase());

  Widget _dateField() {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusField),
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
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
    );
  }

  Widget _typeGrid() {
    return Row(
      children: [
        for (var i = 0; i < _types.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _typeButton(_types[i])),
        ],
      ],
    );
  }

  Widget _typeButton(String type) {
    final selected = type == _selectedType;
    final label = type[0].toUpperCase() + type.substring(1);
    final color = AppColors.forType(type);

    return Material(
      color: selected ? color.withValues(alpha: 0.10) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusField),
      child: InkWell(
        onTap: () => setState(() {
          _selectedType = type;
          if (!_supportsSplit) _splitEnabled = false;
          if (type != 'loan') _isRepayment = false;
        }),
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.55)
                  : AppColors.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _iconForType(type),
                size: 18,
                color: selected ? color : AppColors.inkMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : AppColors.inkSecondary,
                ),
              ),
            ],
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
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 13, color: AppColors.brandGreen),
            SizedBox(width: 4),
            Text(
              'Manage',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.brandGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared look for the two switch rows (repayment / multiple invoices).
  Widget _toggleRow({
    required String label,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: value ? 0.11 : 0.05),
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        border: Border.all(color: color.withValues(alpha: value ? 0.35 : 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: color,
            activeThumbColor: Colors.white,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _repayToggle() {
    return _toggleRow(
      label: 'This is a repayment',
      icon: Icons.south_west,
      color: AppColors.cashIn,
      value: _isRepayment,
      onChanged: (value) => setState(() => _isRepayment = value),
    );
  }

  Widget _splitToggle() {
    return _toggleRow(
      label: 'Multiple invoices',
      icon: Icons.splitscreen_outlined,
      color: AppColors.loan,
      value: _splitEnabled,
      onChanged: (value) => setState(() => _splitEnabled = value),
    );
  }

  Widget _categoryRow(int index, _LineItem item) {
    final categoryName = _categoryName(item.categoryId);
    final hasCategory = categoryName.isNotEmpty;
    final color = hasCategory
        ? AppColors.accentFor(categoryName)
        : AppColors.inkMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconBadge(
                icon: _iconForCategory(categoryName),
                color: color,
                size: 32,
                iconSize: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: item.categoryId,
                  isExpanded: true,
                  items: _categories
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text(
                            c['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => item.categoryId = value),
                  decoration: const InputDecoration(
                    hintText: 'Category',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  hint: Text(
                    'Category',
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: item.amountController,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '${_selectedCurrency.symbol}0',
                    prefixText: '${_selectedCurrency.symbol} ',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 17),
                color: AppColors.inkMuted,
                visualDensity: VisualDensity.compact,
                onPressed: _items.length > 1 ? () => _removeItem(index) : null,
              ),
            ],
          ),
          Divider(height: 1, color: AppColors.hairline),
          Row(
            children: [
              const SizedBox(width: 40),
              Icon(Icons.notes_outlined, size: 15, color: AppColors.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: item.noteController,
                  style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
                  decoration: InputDecoration(
                    hintText: 'Note for this invoice (optional)',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ],
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
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: AppColors.loan.withValues(alpha: 0.4),
            radius: AppStyles.radiusField,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 17, color: AppColors.loan),
                const SizedBox(width: 6),
                Text(
                  'Add invoice',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.loan,
                  ),
                ),
              ],
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
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
