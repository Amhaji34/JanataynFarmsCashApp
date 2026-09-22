import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, this.initialAccount, this.initialDateRange});

  /// Deep-links straight into one account tab (e.g. from a dashboard stat
  /// tile) instead of defaulting to Payroll.
  final String? initialAccount;

  /// Pre-applies a date filter (e.g. "this month") when deep-linking in.
  final DateTimeRange? initialDateRange;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _accounts = ['Payroll', 'Advances', 'Loans', 'Expenses'];

  late String _selectedAccount = widget.initialAccount ?? 'Payroll';

  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _categories = [];

  String? _selectedStaffId;
  String? _selectedPartnerId;
  String? _selectedCategoryName;
  late DateTimeRange? _dateRange = widget.initialDateRange;
  AppCurrency _selectedCurrency = AppCurrency.usd;

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
      if (AppCurrency.fromCode(t['currency'] as String?) != _selectedCurrency) {
        return false;
      }

      if (_selectedAccount == 'Payroll' || _selectedAccount == 'Advances') {
        if (_selectedStaffId != null &&
            t['related_staff_id'] != _selectedStaffId) {
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
        return {
          'Given': given,
          'Deducted': deducted,
          'Outstanding': given - deducted,
        };
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
    final otherTotal = sorted
        .skip(7)
        .fold<double>(0, (sum, e) => sum + e.value);
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
        final categories = _itemsOf(t)
            .map((i) => i['category'] as String? ?? '')
            .where((c) => c.isNotEmpty)
            .toSet();
        return categories.isNotEmpty ? categories.join(', ') : 'Expense';
      default:
        return '';
    }
  }

  Color _rowColor(Map<String, dynamic> t) {
    final type = t['type'] as String;
    if (type == 'advance_deduction') return AppColors.neutral;
    if (type == 'loan_repayment') return AppColors.cashIn;
    return _accountColor;
  }

  /// The accent color for the currently selected account tab.
  Color get _accountColor {
    switch (_selectedAccount) {
      case 'Payroll':
        return AppColors.payroll;
      case 'Advances':
        return AppColors.advance;
      case 'Loans':
        return AppColors.loan;
      case 'Expenses':
        return AppColors.expense;
      default:
        return AppColors.neutral;
    }
  }

  IconData get _accountIcon {
    switch (_selectedAccount) {
      case 'Payroll':
        return Icons.payments_outlined;
      case 'Advances':
        return Icons.pan_tool_alt_outlined;
      case 'Loans':
        return Icons.pan_tool_outlined;
      case 'Expenses':
        return Icons.receipt_long_outlined;
      default:
        return Icons.more_horiz;
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
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        borderSide: const BorderSide(
          color: AppColors.brandGreenLight,
          width: 1.6,
        ),
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget chart,
  }) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: icon,
                color: AppColors.expense,
                size: 34,
                iconSize: 17,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  Widget _barChart(List<MapEntry<String, double>> data) {
    if (data.isEmpty) {
      return const Center(
        child: Text(
          'No data for this range.',
          style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
        ),
      );
    }
    final maxValue = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxValue == 0 ? 1 : maxValue * 1.22,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxValue == 0 ? 1 : maxValue / 2,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: AppColors.hairline,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.ink,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  formatMoney(rod.toY, _selectedCurrency),
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    data[index].key,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                  // Single hue: this is a magnitude comparison, not identity,
                  // so bars share the expense red rather than a rainbow.
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _expenseChartColor.withValues(alpha: 0.72),
                      _expenseChartColor,
                    ],
                  ),
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
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
      appBar: AppBar(title: const Text('Reports')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_errorMessage!)),
            )
          : Column(
              children: [
                // Account type chips, each tinted with its own accent
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _accounts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final account = _accounts[index];
                      final selected = account == _selectedAccount;
                      final chipColor = switch (account) {
                        'Payroll' => AppColors.payroll,
                        'Advances' => AppColors.advance,
                        'Loans' => AppColors.loan,
                        'Expenses' => AppColors.expense,
                        _ => AppColors.neutral,
                      };
                      return ChoiceChip(
                        label: Text(account),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _selectedAccount = account;
                          _selectedStaffId = null;
                          _selectedPartnerId = null;
                          _selectedCategoryName = null;
                        }),
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Currency toggle - a bar chart can't sensibly overlay two
                // currencies on one axis, so Reports always views one
                // currency at a time (this narrows the summary cards and
                // both charts).
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: CurrencyToggle(
                    value: _selectedCurrency,
                    onChanged: (value) =>
                        setState(() => _selectedCurrency = value),
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
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _dateRange == null
                              ? AppColors.inkSecondary
                              : AppColors.brandGreen,
                          backgroundColor: _dateRange == null
                              ? AppColors.surface
                              : AppColors.brandGreen.withValues(alpha: 0.08),
                          side: BorderSide(
                            color: _dateRange == null
                                ? AppColors.hairline
                                : AppColors.brandGreen.withValues(alpha: 0.35),
                          ),
                        ),
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 15,
                        ),
                        label: Text(
                          _dateRange == null
                              ? 'Date'
                              : '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_dateRange != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: AppColors.inkMuted,
                          onPressed: () => setState(() => _dateRange = null),
                        ),
                    ],
                  ),
                ),

                // Summary cards
                SizedBox(
                  height: 82,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: summary.entries.map((e) {
                      // "Outstanding" is the headline number — give it the
                      // account's accent; supporting figures stay neutral.
                      final isHeadline =
                          e.key == 'Outstanding' || e.key.startsWith('Total');
                      final color = isHeadline
                          ? _accountColor
                          : AppColors.inkSecondary;
                      return Container(
                        width: 138,
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: isHeadline
                            ? AppStyles.accentCard(_accountColor)
                            : AppStyles.card,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              e.key,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              formatMoney(e.value, _selectedCurrency),
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
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: _selectedAccount == 'Expenses'
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            _chartCard(
                              title: 'Spending by category',
                              subtitle: 'Top categories in this range',
                              icon: Icons.pie_chart_outline,
                              chart: _barChart(_categoryChartData),
                            ),
                            const SizedBox(height: 12),
                            _chartCard(
                              title: 'Spending by month',
                              subtitle: 'Last 6 months with activity',
                              icon: Icons.show_chart,
                              chart: _barChart(_monthlyChartData),
                            ),
                          ],
                        )
                      : filtered.isEmpty
                      ? EmptyState(
                          icon: _accountIcon,
                          title: 'Nothing to report yet',
                          subtitle:
                              'No $_selectedAccount records match these '
                              'filters.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
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

                            return AppCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  IconBadge(
                                    icon: isIn
                                        ? Icons.south_west
                                        : isNeutral
                                        ? Icons.sync_alt
                                        : _accountIcon,
                                    color: color,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _rowTitle(t),
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _dateFormat.format(date),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    isNeutral
                                        ? formatMoney(amount, _selectedCurrency)
                                        : '${isIn ? '+' : '-'}${formatMoney(amount, _selectedCurrency)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                      color: isNeutral
                                          ? AppColors.inkMuted
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
