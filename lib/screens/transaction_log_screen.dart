import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import 'add_transaction_screen.dart';

class TransactionLogScreen extends StatefulWidget {
  const TransactionLogScreen({super.key});

  @override
  State<TransactionLogScreen> createState() => _TransactionLogScreenState();
}

class _TransactionLogScreenState extends State<TransactionLogScreen> {
  final List<Map<String, String>> _filters = [
    {'label': 'All', 'value': 'all'},
    {'label': 'Expenses', 'value': 'expense'},
    {'label': 'Payroll', 'value': 'payroll'},
    {'label': 'Loans', 'value': 'loan'},
    {'label': 'Advances', 'value': 'advance'},
  ];
  String _selectedFilter = 'all';

  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _transactions = [];
  String? _role;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  DateTimeRange? _dateRange;

  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _dateFormat = DateFormat('MMM d');

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadTransactions();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  Future<void> _loadRole() async {
    final userId = supabase.auth.currentUser!.id;
    final profile = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .single();
    setState(() => _role = profile['role'] as String?);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('transactions')
          .select(
            '*, partners(name), staff(name), transaction_items(id, category, amount)',
          )
          .order('transaction_date', ascending: false);

      setState(() {
        _transactions = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load transactions: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> t) =>
      List<Map<String, dynamic>>.from(t['transaction_items'] ?? []);

  bool _matchesSearch(Map<String, dynamic> t) {
    if (_searchQuery.isEmpty) return true;

    final note = (t['note'] as String? ?? '').toLowerCase();
    if (note.contains(_searchQuery)) return true;

    final partnerName = (t['partners']?['name'] as String? ?? '').toLowerCase();
    if (partnerName.contains(_searchQuery)) return true;

    final staffName = (t['staff']?['name'] as String? ?? '').toLowerCase();
    if (staffName.contains(_searchQuery)) return true;

    final items = _itemsOf(t);
    for (final item in items) {
      final category = (item['category'] as String? ?? '').toLowerCase();
      if (category.contains(_searchQuery)) return true;
    }
    return false;
  }

  bool _matchesDate(Map<String, dynamic> t) {
    if (_dateRange == null) return true;
    final date = DateTime.parse(t['transaction_date'] as String);
    final start = DateTime(
      _dateRange!.start.year,
      _dateRange!.start.month,
      _dateRange!.start.day,
    );
    final end = DateTime(
      _dateRange!.end.year,
      _dateRange!.end.month,
      _dateRange!.end.day,
      23,
      59,
      59,
    );
    return date.isAfter(start.subtract(const Duration(seconds: 1))) &&
        date.isBefore(end);
  }

  // Transactions after search + date filters, but before the type chip filter.
  // Used to compute per-category totals so you can see the full breakdown regardless
  // of which chip is selected.
  List<Map<String, dynamic>> get _searchAndDateFiltered {
    return _transactions
        .where((t) => _matchesSearch(t) && _matchesDate(t))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    return _searchAndDateFiltered
        .where((t) => _selectedFilter == 'all' || t['type'] == _selectedFilter)
        .toList();
  }

  Map<String, double> get _categoryTotals {
    final totals = <String, double>{
      'expense': 0,
      'payroll': 0,
      'loan': 0,
      'advance': 0,
    };
    for (final t in _searchAndDateFiltered) {
      final type = t['type'] as String;
      if (!totals.containsKey(type))
        continue; // skip loan_repayment / advance_deduction
      totals[type] = totals[type]! + (t['amount'] as num).toDouble();
    }
    return totals;
  }

  bool _isCashIn(String type) => type == 'loan_repayment';
  bool _isNeutral(String type) => type == 'advance_deduction';

  IconData _iconFor(String type) {
    switch (type) {
      case 'expense':
        return Icons.receipt_long_outlined;
      case 'payroll':
        return Icons.payments_outlined;
      case 'loan':
        return Icons.pan_tool_outlined;
      case 'advance':
        return Icons.pan_tool_alt_outlined;
      case 'loan_repayment':
      case 'advance_deduction':
        return Icons.arrow_downward;
      default:
        return Icons.more_horiz;
    }
  }

  Color _colorFor(String type) {
    if (_isCashIn(type)) return Colors.green;
    if (_isNeutral(type)) return Colors.grey;
    switch (type) {
      case 'expense':
        return Colors.red;
      case 'payroll':
        return Colors.orange;
      case 'loan':
        return Colors.blue;
      case 'advance':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _typeLabel(String type) =>
      type[0].toUpperCase() + type.substring(1).replaceAll('_', ' ');

  /// Title logic:
  /// - If there's a related partner/staff, that takes priority (e.g. "Loan · Fatima").
  /// - Else for expense transactions, title = the category name(s) — every
  ///   invoice's category, joined, whether there's one or several.
  /// - Else title = the note if present, falling back to the type label.
  String _titleFor(Map<String, dynamic> t) {
    final type = t['type'] as String;
    final label = _typeLabel(type);

    final partnerName = t['partners']?['name'] as String?;
    final staffName = t['staff']?['name'] as String?;
    if (partnerName != null) return '$label · $partnerName';
    if (staffName != null) return '$label · $staffName';

    if (type == 'expense') {
      final categories = _itemsOf(t)
          .map((i) => i['category'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .join(', ');
      if (categories.isNotEmpty) return categories;
    }

    final note = (t['note'] as String? ?? '').trim();
    return note.isNotEmpty ? note : label;
  }

  /// Subtitle: category breakdown when split, otherwise the date.
  Widget _subtitleFor(Map<String, dynamic> t, DateTime date) {
    final items = _itemsOf(t);
    final dateText = _dateFormat.format(date);

    if (items.length > 1) {
      final breakdown = items
          .map(
            (i) =>
                '${i['category']} ${_currency.format((i['amount'] as num).toDouble())}',
          )
          .join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            breakdown,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 2),
          Text(
            dateText,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      );
    }

    return Text(
      dateText,
      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  void _clearDateRange() => setState(() => _dateRange = null);

  Future<void> _openEditSheet(Map<String, dynamic> t) async {
    final isSplit = _itemsOf(t).length > 1;

    final saved = isSplit
        ? await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTransactionScreen(existingTransaction: t),
            ),
          )
        : await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _EditTransactionSheet(transaction: t),
          );

    if (saved == true) {
      _loadTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _categoryTotals;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        title: const Text('Transactions'),
        backgroundColor: const Color(0xFFF7F7F5),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadTransactions,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            : Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search fuel, fencing, water...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),

                  // Date filter row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDateRange,
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 15,
                            ),
                            label: Text(
                              _dateRange == null
                                  ? 'Filter by date'
                                  : '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        if (_dateRange != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _clearDateRange,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Category totals
                  SizedBox(
                    height: 74,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _totalCard('Expenses', totals['expense']!, Colors.red),
                        _totalCard(
                          'Payroll',
                          totals['payroll']!,
                          Colors.orange,
                        ),
                        _totalCard('Loans', totals['loan']!, Colors.blue),
                        _totalCard(
                          'Advances',
                          totals['advance']!,
                          Colors.purple,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Type filter chips
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      itemCount: _filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final filter = _filters[index];
                        final selected = filter['value'] == _selectedFilter;
                        return ChoiceChip(
                          label: Text(filter['label']!),
                          selected: selected,
                          onSelected: (_) => setState(
                            () => _selectedFilter = filter['value']!,
                          ),
                        );
                      },
                    ),
                  ),

                  Expanded(
                    child: _filteredTransactions.isEmpty
                        ? const Center(child: Text('No transactions found.'))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredTransactions.length,
                            itemBuilder: (context, index) {
                              final t = _filteredTransactions[index];
                              final type = t['type'] as String;
                              final amount = (t['amount'] as num).toDouble();
                              final date = DateTime.parse(
                                t['transaction_date'] as String,
                              );
                              final color = _colorFor(type);
                              final isIn = _isCashIn(type);
                              final isNeutral = _isNeutral(type);

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _iconFor(type),
                                        size: 16,
                                        color: color,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _titleFor(t),
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          _subtitleFor(t, date),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isNeutral
                                              ? _currency.format(amount)
                                              : '${isIn ? '+' : '-'}${_currency.format(amount)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: isNeutral
                                                ? Colors.grey[600]
                                                : color,
                                          ),
                                        ),
                                        if (_role == 'admin')
                                          InkWell(
                                            onTap: () => _openEditSheet(t),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Icon(
                                                Icons.edit_outlined,
                                                size: 16,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _totalCard(String label, double value, Color color) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            _currency.format(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _EditTransactionSheet extends StatefulWidget {
  const _EditTransactionSheet({required this.transaction});

  final Map<String, dynamic> transaction;

  @override
  State<_EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<_EditTransactionSheet> {
  static const _borderColor = Color(0xFFE5E5E5);

  late DateTime _selectedDate;
  late final TextEditingController _noteController;
  late final TextEditingController _amountController;
  late final List<Map<String, dynamic>> _items;

  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _selectedDate = DateTime.parse(t['transaction_date'] as String);
    _noteController = TextEditingController(text: t['note'] as String? ?? '');
    _items = List<Map<String, dynamic>>.from(t['transaction_items'] ?? []);
    _amountController = TextEditingController(
      text: (t['amount'] as num).toDouble().toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _typeLabel(String type) =>
      type[0].toUpperCase() + type.substring(1).replaceAll('_', ' ');

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

    final newAmount = double.tryParse(_amountController.text) ?? 0;
    if (newAmount <= 0) {
      setState(() => _errorMessage = 'Enter an amount greater than zero.');
      return;
    }

    setState(() => _saving = true);
    try {
      final t = widget.transaction;
      await supabase.from('transactions').update({
        'transaction_date': _dbDateFormat.format(_selectedDate),
        'note': _noteController.text.trim(),
        'amount': newAmount,
      }).eq('id', t['id']);

      if (_items.isNotEmpty) {
        await supabase
            .from('transaction_items')
            .update({'amount': newAmount})
            .eq('id', _items.first['id']);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
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
    final t = widget.transaction;
    final type = t['type'] as String;
    final label = _typeLabel(type);
    final subtitle = _items.isNotEmpty
        ? '$label · ${_items.first['category']}'
        : label;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F7F5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit transaction',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),

            Text(
              'Date',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dateFormat.format(_selectedDate),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Amount',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: _fieldDecoration().copyWith(prefixText: '\$ '),
            ),
            const SizedBox(height: 20),

            Text(
              'Note',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              decoration: _fieldDecoration(hint: 'Add a note'),
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save changes',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
