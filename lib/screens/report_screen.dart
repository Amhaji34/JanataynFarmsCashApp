import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _accounts = ['Payroll', 'Advances', 'Loans', 'Expenses'];

  static const _borderColor = Color(0xFFE5E5E5);

  String _selectedAccount = 'Payroll';

  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _categories = [];

  String? _selectedStaffId;
  String? _selectedPartnerId;
  String? _selectedCategoryName;
  DateTimeRange? _dateRange;

  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _monthLabelFormat = DateFormat('MMM');

  // Single-hue sequential ramp (magnitude, not identity) in this app's
  // established expense=red color, light -> dark.
  static const _expenseChartColor = Color(0xFFE34948);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final txns = await supabase
          .from('transactions')
          .select(
            '*, partners(name), staff(name), transaction_items(category, amount)',
          )
          .order('transaction_date', ascending: false);
      final staff = await supabase.from('staff').select().order('name');
      final partners = await supabase.from('partners').select().order('name');
      final categories = await supabase
          .from('expense_categories')
          .select()
          .order('name');

      setState(() {
        _transactions = List<Map<String, dynamic>>.from(txns);
        _staff = List<Map<String, dynamic>>.from(staff);
        _partners = List<Map<String, dynamic>>.from(partners);
        _categories = List<Map<String, dynamic>>.from(categories);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load report: $e';
        _loading = false;
      });
    }
  }

  Set<String> get _accountTypes {
    switch (_selectedAccount) {
      case 'Payroll':
        return {'payroll'};
      case 'Advances':
        return {'advance', 'advance_deduction'};
      case 'Loans':
        return {'loan', 'loan_repayment'};
      case 'Expenses':
        return {'expense'};
      default:
        return {};
    }
  }

  List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> t) =>
      List<Map<String, dynamic>>.from(t['transaction_items'] ?? []);

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
    return !date.isBefore(start) && !date.isAfter(end);
  }

  List<Map<String, dynamic>> get _filtered {
    final types = _accountTypes;
    return _transactions.where((t) {
      if (!types.contains(t['type'])) return false;
      if (!_matchesDate(t)) return false;

      if (_selectedAccount == 'Payroll' || _selectedAccount == 'Advances') {
        if (_selectedStaffId != null && t['related_staff_id'] != _selectedStaffId) {
          return false;
        }
      }
      if (_selectedAccount == 'Loans') {
        if (_selectedPartnerId != null &&
            t['related_partner_id'] != _selectedPartnerId) {
          return false;
        }
      }
      if (_selectedAccount == 'Expenses' && _selectedCategoryName != null) {
        final matches = _itemsOf(
          t,
        ).any((i) => i['category'] == _selectedCategoryName);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  Map<String, double> get _summary {
    final filtered = _filtered;
    switch (_selectedAccount) {
      case 'Payroll':
        final total = filtered.fold<double>(
          0,
          (sum, t) => sum + (t['amount'] as num).toDouble(),
        );
        return {'Total paid': total};
      case 'Advances':
        double given = 0, deducted = 0;
        for (final t in filtered) {
          final amount = (t['amount'] as num).toDouble();
          if (t['type'] == 'advance') {
            given += amount;
          } else {
            deducted += amount;
          }
        }
        return {'Given': given, 'Deducted': deducted, 'Outstanding': given - deducted};
      case 'Loans':
        double lent = 0, repaid = 0;
        for (final t in filtered) {
          final amount = (t['amount'] as num).toDouble();
          if (t['type'] == 'loan') {
            lent += amount;
          } else {
            repaid += amount;
          }
        }
        return {'Lent': lent, 'Repaid': repaid, 'Outstanding': lent - repaid};
      case 'Expenses':
        final total = filtered.fold<double>(
          0,
          (sum, t) => sum + (t['amount'] as num).toDouble(),
        );
        return {'Total spent': total};
      default:
        return {};
    }
  }

  /// Spend per category, sorted descending, capped to the top 7 with the
  /// remainder folded into "Other" so the chart stays readable.
  List<MapEntry<String, double>> get _categoryChartData {
    final totals = <String, double>{};
    for (final t in _filtered) {
      for (final item in _itemsOf(t)) {
        final category = item['category'] as String? ?? '';
        if (category.isEmpty) continue;
        final amount = (item['amount'] as num).toDouble();
        totals[category] = (totals[category] ?? 0) + amount;
      }
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.length <= 7) return sorted;
    final top = sorted.take(7).toList();
    final otherTotal = sorted.skip(7).fold<double>(0, (sum, e) => sum + e.value);
    top.add(MapEntry('Other', otherTotal));
    return top;
  }

  /// Spend per month, chronological, capped to the most recent 6 months
  /// present in the filtered data.
  List<MapEntry<String, double>> get _monthlyChartData {
    final totals = <DateTime, double>{};
    for (final t in _filtered) {
      final date = DateTime.parse(t['transaction_date'] as String);
      final key = DateTime(date.year, date.month);
      final amount = (t['amount'] as num).toDouble();
      totals[key] = (totals[key] ?? 0) + amount;
    }
    final sortedKeys = totals.keys.toList()..sort();
    final recentKeys = sortedKeys.length <= 6
        ? sortedKeys
        : sortedKeys.sublist(sortedKeys.length - 6);
    return recentKeys
        .map((k) => MapEntry(_monthLabelFormat.format(k), totals[k]!))
        .toList();
  }

  String _rowTitle(Map<String, dynamic> t) {
    final type = t['type'] as String;
    switch (_selectedAccount) {
      case 'Payroll':
        return t['staff']?['name'] as String? ?? 'Payroll';
      case 'Advances':
        final name = t['staff']?['name'] as String? ?? '';
        return type == 'advance' ? '$name · Advance given' : '$name · Deducted';
      case 'Loans':
        final name = t['partners']?['name'] as String? ?? '';
        return type == 'loan' ? '$name · Loan given' : '$name · Repayment';
      case 'Expenses':
        final categories = _itemsOf(
          t,
        ).map((i) => i['category'] as String? ?? '').where((c) => c.isNotEmpty).toSet();
        return categories.isNotEmpty ? categories.join(', ') : 'Expense';
      default:
        return '';
    }
  }

  Color _rowColor(Map<String, dynamic> t) {
    final type = t['type'] as String;
    if (type == 'advance_deduction') return Colors.grey;
    if (type == 'loan_repayment') return Colors.green;
    switch (_selectedAccount) {
      case 'Payroll':
        return Colors.orange;
      case 'Advances':
        return Colors.purple;
      case 'Loans':
        return Colors.blue;
      case 'Expenses':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool _isCashIn(String type) => type == 'loan_repayment';
  bool _isNeutral(String type) => type == 'advance_deduction';

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  InputDecoration _dropdownDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderColor),
      ),
    );
  }

  Widget _chartCard({required String title, required Widget chart}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  Widget _barChart(List<MapEntry<String, double>> data) {
    if (data.isEmpty) {
      return const Center(
        child: Text('No data.', style: TextStyle(color: Colors.grey)),
      );
    }
    final maxValue = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxValue == 0 ? 1 : maxValue * 1.2,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              _currency.format(rod.toY),
              const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    data[index].key,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].value,
                  color: _expenseChartColor,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final summary = _summary;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: const Color(0xFFF7F7F5),
        elevation: 0,
      ),
      body: _loading
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
                // Account type chips
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    itemCount: _accounts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final account = _accounts[index];
                      final selected = account == _selectedAccount;
                      return ChoiceChip(
                        label: Text(account),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _selectedAccount = account;
                          _selectedStaffId = null;
                          _selectedPartnerId = null;
                          _selectedCategoryName = null;
                        }),
                      );
                    },
                  ),
                ),

                // Filters
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      if (_selectedAccount == 'Payroll' ||
                          _selectedAccount == 'Advances')
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedStaffId,
                            decoration: _dropdownDecoration('All staff'),
                            hint: const Text('All staff'),
                            items: _staff
                                .map(
                                  (s) => DropdownMenuItem<String>(
                                    value: s['id'] as String,
                                    child: Text(s['name'] as String),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedStaffId = value),
                          ),
                        ),
                      if (_selectedAccount == 'Loans')
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedPartnerId,
                            decoration: _dropdownDecoration('All partners'),
                            hint: const Text('All partners'),
                            items: _partners
                                .map(
                                  (p) => DropdownMenuItem<String>(
                                    value: p['id'] as String,
                                    child: Text(p['name'] as String),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedPartnerId = value),
                          ),
                        ),
                      if (_selectedAccount == 'Expenses')
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCategoryName,
                            decoration: _dropdownDecoration('All categories'),
                            hint: const Text('All categories'),
                            items: _categories
                                .map(
                                  (c) => DropdownMenuItem<String>(
                                    value: c['name'] as String,
                                    child: Text(c['name'] as String),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedCategoryName = value),
                          ),
                        ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _pickDateRange,
                        icon: const Icon(Icons.calendar_today_outlined, size: 15),
                        label: Text(
                          _dateRange == null
                              ? 'Date'
                              : '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (_dateRange != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _dateRange = null),
                        ),
                    ],
                  ),
                ),

                // Summary cards
                SizedBox(
                  height: 74,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: summary.entries
                        .map(
                          (e) => Container(
                            width: 130,
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
                                Text(
                                  e.key,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currency.format(e.value),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: _selectedAccount == 'Expenses'
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            _chartCard(
                              title: 'Spending by category',
                              chart: _barChart(_categoryChartData),
                            ),
                            const SizedBox(height: 12),
                            _chartCard(
                              title: 'Spending by month',
                              chart: _barChart(_monthlyChartData),
                            ),
                          ],
                        )
                      : filtered.isEmpty
                      ? const Center(child: Text('No transactions found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final t = filtered[index];
                            final type = t['type'] as String;
                            final amount = (t['amount'] as num).toDouble();
                            final date = DateTime.parse(
                              t['transaction_date'] as String,
                            );
                            final color = _rowColor(t);
                            final isIn = _isCashIn(type);
                            final isNeutral = _isNeutral(type);

                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _rowTitle(t),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _dateFormat.format(date),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
