import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'add_transaction_screen.dart';

class TransactionLogScreen extends StatefulWidget {
  const TransactionLogScreen({super.key, this.initialDateRange});

  /// Pre-applies a date filter (e.g. "this month") when deep-linking in
  /// from a dashboard stat tile.
  final DateTimeRange? initialDateRange;

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
    {'label': 'Transfers', 'value': 'transfer'},
  ];
  String _selectedFilter = 'all';

  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _transactions = [];
  String? _role;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  late DateTimeRange? _dateRange = widget.initialDateRange;
  AppCurrency _totalsCurrency = AppCurrency.usd;

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

      // Petty Cash transfers (to/from Investment, Loans, Revenue) are a
      // separate ledger (account_transactions) but the user wants to see
      // them alongside regular transactions here, since they move the same
      // cash-on-hand balance.
      final accountsData = await supabase.from('accounts').select();
      final accounts = List<Map<String, dynamic>>.from(accountsData);
      final accountNameById = {
        for (final a in accounts) a['id'] as String: a['name'] as String,
      };
      final pettyCash = accounts.firstWhere((a) => a['name'] == 'Petty Cash');
      final pettyCashId = pettyCash['id'] as String;

      final transfersData = await supabase
          .from('account_transactions')
          .select()
          .eq('account_id', pettyCashId);
      final transferRows = List<Map<String, dynamic>>.from(transfersData)
          .where(
            (t) => t['type'] == 'transfer_in' || t['type'] == 'transfer_out',
          )
          .map((t) {
            final relatedId = t['related_account_id'] as String?;
            final relatedName = relatedId != null
                ? (accountNameById[relatedId] ?? 'Account')
                : 'Account';
            return <String, dynamic>{
              'id': t['id'],
              'type': t['type'],
              'amount': t['amount'],
              'currency': t['currency'],
              'transaction_date': t['transaction_date'],
              'note': t['note'],
              'related_account_name': relatedName,
              'is_transfer': true,
            };
          })
          .toList();

      final merged = [...List<Map<String, dynamic>>.from(data), ...transferRows]
        ..sort(
          (a, b) => (b['transaction_date'] as String).compareTo(
            a['transaction_date'] as String,
          ),
        );

      setState(() {
        _transactions = merged;
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
    return _searchAndDateFiltered.where((t) {
      if (_selectedFilter == 'all') return true;
      if (_selectedFilter == 'transfer') {
        return t['type'] == 'transfer_in' || t['type'] == 'transfer_out';
      }
      return t['type'] == _selectedFilter;
    }).toList();
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
      // skip loan_repayment / advance_deduction
      if (!totals.containsKey(type)) {
        continue;
      }
      if (AppCurrency.fromCode(t['currency'] as String?) != _totalsCurrency) {
        continue;
      }
      totals[type] = totals[type]! + (t['amount'] as num).toDouble();
    }
    return totals;
  }

  bool _isCashIn(String type) =>
      type == 'loan_repayment' || type == 'transfer_in';
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
      case 'transfer_in':
        return Icons.call_received;
      case 'transfer_out':
        return Icons.call_made;
      default:
        return Icons.more_horiz;
    }
  }

  Color _colorFor(String type) => AppColors.forType(type);

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

    if (type == 'transfer_in' || type == 'transfer_out') {
      final relatedName = t['related_account_name'] as String? ?? 'Account';
      return type == 'transfer_in'
          ? 'Transfer from $relatedName'
          : 'Transfer to $relatedName';
    }

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
    final currency = AppCurrency.fromCode(t['currency'] as String?);

    if (items.length > 1) {
      final breakdown = items
          .map(
            (i) =>
                '${i['category']} ${formatMoney((i['amount'] as num).toDouble(), currency)}',
          )
          .join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            breakdown,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.inkSecondary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            dateText,
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      );
    }

    return Text(
      dateText,
      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
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
      appBar: AppBar(title: const Text('Transactions')),
      body: RefreshIndicator(
        onRefresh: _loadTransactions,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: ErrorNote(_errorMessage!)),
              )
            : Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search fuel, fencing, water...',
                        isDense: true,
                        prefixIcon: Icon(
                          Icons.search,
                          size: 20,
                          color: AppColors.inkMuted,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                color: AppColors.inkMuted,
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
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
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _dateRange == null
                                  ? AppColors.inkSecondary
                                  : AppColors.brandGreen,
                              backgroundColor: _dateRange == null
                                  ? AppColors.surface
                                  : AppColors.brandGreen.withValues(
                                      alpha: 0.08,
                                    ),
                              side: BorderSide(
                                color: _dateRange == null
                                    ? AppColors.hairline
                                    : AppColors.brandGreen.withValues(
                                        alpha: 0.35,
                                      ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 15,
                            ),
                            label: Text(
                              _dateRange == null
                                  ? 'Filter by date'
                                  : '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_dateRange != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: AppColors.inkMuted,
                            onPressed: _clearDateRange,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Totals currency toggle - narrows the totals below, not
                  // the list (each row still shows its own currency).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          'Totals in:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CurrencyToggle(
                            value: _totalsCurrency,
                            onChanged: (value) =>
                                setState(() => _totalsCurrency = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Per-type totals
                  SizedBox(
                    height: 82,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _totalCard(
                          'Expenses',
                          totals['expense']!,
                          AppColors.expense,
                          Icons.receipt_long_outlined,
                        ),
                        _totalCard(
                          'Payroll',
                          totals['payroll']!,
                          AppColors.payroll,
                          Icons.payments_outlined,
                        ),
                        _totalCard(
                          'Loans',
                          totals['loan']!,
                          AppColors.loan,
                          Icons.pan_tool_outlined,
                        ),
                        _totalCard(
                          'Advances',
                          totals['advance']!,
                          AppColors.advance,
                          Icons.pan_tool_alt_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Type filter chips, tinted with each type's own color
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final filter = _filters[index];
                        final value = filter['value']!;
                        final selected = value == _selectedFilter;
                        final chipColor = value == 'all'
                            ? AppColors.brandGreen
                            : AppColors.forType(value);
                        return ChoiceChip(
                          label: Text(filter['label']!),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedFilter = value),
                          selectedColor: chipColor,
                          backgroundColor: AppColors.surface,
                          side: BorderSide(
                            color: selected ? chipColor : AppColors.hairline,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : AppColors.inkSecondary,
                          ),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: _filteredTransactions.isEmpty
                        ? const EmptyState(
                            icon: Icons.search_off_outlined,
                            title: 'No transactions found',
                            subtitle:
                                'Try clearing your search or date filter.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: _filteredTransactions.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final t = _filteredTransactions[index];
                              final type = t['type'] as String;
                              final amount = (t['amount'] as num).toDouble();
                              final currency = AppCurrency.fromCode(
                                t['currency'] as String?,
                              );
                              final date = DateTime.parse(
                                t['transaction_date'] as String,
                              );
                              final color = _colorFor(type);
                              final isIn = _isCashIn(type);
                              final isNeutral = _isNeutral(type);

                              return AppCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    IconBadge(
                                      icon: _iconFor(type),
                                      color: color,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _titleFor(t),
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          _subtitleFor(t, date),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isNeutral
                                              ? formatMoney(amount, currency)
                                              : '${isIn ? '+' : '-'}${formatMoney(amount, currency)}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                            color: isNeutral
                                                ? AppColors.inkMuted
                                                : color,
                                          ),
                                        ),
                                        if (_role == 'admin' &&
                                            t['is_transfer'] != true)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: InkWell(
                                              onTap: () => _openEditSheet(t),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.canvas,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.edit_outlined,
                                                      size: 13,
                                                      color: AppColors.inkMuted,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Edit',
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            AppColors.inkMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
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

  Widget _totalCard(String label, double value, Color color, IconData icon) {
    return Container(
      width: 132,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: AppStyles.accentCard(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            formatMoney(value, _totalsCurrency),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
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
  late DateTime _selectedDate;
  late final TextEditingController _noteController;
  late final TextEditingController _amountController;
  late final List<Map<String, dynamic>> _items;
  late AppCurrency _selectedCurrency;

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
    _selectedCurrency = AppCurrency.fromCode(t['currency'] as String?);
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
      await supabase
          .from('transactions')
          .update({
            'transaction_date': _dbDateFormat.format(_selectedDate),
            'note': _noteController.text.trim(),
            'amount': newAmount,
            'currency': _selectedCurrency.code,
          })
          .eq('id', t['id']);

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

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final type = t['type'] as String;
    final label = _typeLabel(type);
    final subtitle = _items.isNotEmpty
        ? '$label · ${_items.first['category']}'
        : label;
    final accent = AppColors.forType(type);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  IconBadge(
                    icon: Icons.edit_outlined,
                    color: accent,
                    size: 40,
                    iconSize: 19,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit transaction',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.inkMuted,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const SectionLabel('DATE'),
              const SizedBox(height: 7),
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
              const SizedBox(height: 18),

              const SectionLabel('CURRENCY'),
              const SizedBox(height: 7),
              CurrencyToggle(
                value: _selectedCurrency,
                onChanged: (value) => setState(() => _selectedCurrency = value),
              ),
              const SizedBox(height: 18),

              const SectionLabel('AMOUNT'),
              const SizedBox(height: 7),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                decoration: InputDecoration(
                  prefixText: '${_selectedCurrency.symbol} ',
                  prefixStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              const SectionLabel('NOTE'),
              const SizedBox(height: 7),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(hintText: 'Add a note'),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                ErrorNote(_errorMessage!),
              ],
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
