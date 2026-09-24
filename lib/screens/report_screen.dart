import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'category_invoices_screen.dart';

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
            '*, partners(name), staff(name), '
            'transaction_items(id, category, amount, note)',
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

  /// A transaction's amount for display/summing purposes. When a category
  /// filter is active, a multi-invoice transaction can match on just one
  /// of its several line items - summing/showing the transaction's full
  /// amount in that case would double-count the categories that aren't
  /// actually selected, so this sums only the matching item(s) instead.
  double _expenseAmountFor(Map<String, dynamic> t) {
    if (_selectedAccount == 'Expenses' && _selectedCategoryName != null) {
      return _itemsOf(t)
          .where((i) => i['category'] == _selectedCategoryName)
          .fold<double>(0, (sum, i) => sum + (i['amount'] as num).toDouble());
    }
    return (t['amount'] as num).toDouble();
  }

  Map<AppCurrency, double> _zeroByCurrency() => {
    for (final c in AppCurrency.values) c: 0.0,
  };

  /// Every summary figure is per-currency (never blended - see
  /// claude.md's "Currencies" section), so each metric maps to a
  /// USD/SLSH breakdown rather than one number. The summary card row
  /// below renders two cards per metric, one per currency.
  Map<String, Map<AppCurrency, double>> get _summary {
    final filtered = _filtered;
    switch (_selectedAccount) {
      case 'Payroll':
        final total = _zeroByCurrency();
        for (final t in filtered) {
          final c = AppCurrency.fromCode(t['currency'] as String?);
          total[c] = (total[c] ?? 0) + (t['amount'] as num).toDouble();
        }
        return {'Total paid': total};
      case 'Advances':
        final given = _zeroByCurrency();
        final deducted = _zeroByCurrency();
        for (final t in filtered) {
          final c = AppCurrency.fromCode(t['currency'] as String?);
          final amount = (t['amount'] as num).toDouble();
          if (t['type'] == 'advance') {
            given[c] = (given[c] ?? 0) + amount;
          } else {
            deducted[c] = (deducted[c] ?? 0) + amount;
          }
        }
        final outstanding = {
          for (final c in AppCurrency.values)
            c: (given[c] ?? 0) - (deducted[c] ?? 0),
        };
        return {
          'Given': given,
          'Deducted': deducted,
          'Outstanding': outstanding,
        };
      case 'Loans':
        final lent = _zeroByCurrency();
        final repaid = _zeroByCurrency();
        for (final t in filtered) {
          final c = AppCurrency.fromCode(t['currency'] as String?);
          final amount = (t['amount'] as num).toDouble();
          if (t['type'] == 'loan') {
            lent[c] = (lent[c] ?? 0) + amount;
          } else {
            repaid[c] = (repaid[c] ?? 0) + amount;
          }
        }
        final outstanding = {
          for (final c in AppCurrency.values)
            c: (lent[c] ?? 0) - (repaid[c] ?? 0),
        };
        return {'Lent': lent, 'Repaid': repaid, 'Outstanding': outstanding};
      case 'Expenses':
        final total = _zeroByCurrency();
        for (final t in filtered) {
          final c = AppCurrency.fromCode(t['currency'] as String?);
          total[c] = (total[c] ?? 0) + _expenseAmountFor(t);
        }
        return {'Total spent': total};
      default:
        return {};
    }
  }

  /// Spend per category for one currency, sorted descending, capped to
  /// the top 7 with the remainder folded into "Other" so the chart stays
  /// readable. A bar chart can't sensibly overlay two currencies on one
  /// axis, so this renders as one chart card per currency that actually
  /// has data - see the build method.
  List<MapEntry<String, double>> _categoryChartData(AppCurrency currency) {
    final totals = <String, double>{};
    for (final t in _filtered) {
      if (AppCurrency.fromCode(t['currency'] as String?) != currency) {
        continue;
      }
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

  /// Every `transaction_items` row matching the selected category,
  /// flattened with its parent transaction's date/currency/note - what
  /// CategoryInvoicesScreen shows as cards. Only meaningful once a
  /// category is actually selected.
  List<CategoryInvoice> get _categoryInvoices {
    if (_selectedCategoryName == null) return [];
    final invoices = <CategoryInvoice>[];
    for (final t in _filtered) {
      final items = _itemsOf(t);
      final matching = items.where(
        (i) => i['category'] == _selectedCategoryName,
      );
      final otherCategories = items
          .where((i) => i['category'] != _selectedCategoryName)
          .map((i) => i['category'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();
      for (final item in matching) {
        invoices.add(
          CategoryInvoice(
            transactionId: t['id'] as String,
            itemId: item['id'] as String,
            date: DateTime.parse(t['transaction_date'] as String),
            amount: (item['amount'] as num).toDouble(),
            currency: AppCurrency.fromCode(t['currency'] as String?),
            itemNote: item['note'] as String?,
            transactionNote: (t['note'] as String? ?? '').trim(),
            otherCategories: otherCategories,
          ),
        );
      }
    }
    invoices.sort((a, b) => b.date.compareTo(a.date));
    return invoices;
  }

  /// Spend per month for one currency, chronological, capped to the most
  /// recent 6 months present in the filtered data.
  List<MapEntry<String, double>> _monthlyChartData(AppCurrency currency) {
    final totals = <DateTime, double>{};
    for (final t in _filtered) {
      if (AppCurrency.fromCode(t['currency'] as String?) != currency) {
        continue;
      }
      final date = DateTime.parse(t['transaction_date'] as String);
      final key = DateTime(date.year, date.month);
      totals[key] = (totals[key] ?? 0) + _expenseAmountFor(t);
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

  void _openCategoryInvoices(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryInvoicesScreen(
          categoryName: _selectedCategoryName!,
          invoices: _categoryInvoices,
        ),
      ),
    );
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
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
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

  Widget _barChart(List<MapEntry<String, double>> data, AppCurrency currency) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No data for this range.',
          style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
        ),
      );
    }
    final maxValue = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Each label gets boxed to its own bar's slot width - without
        // this, fl_chart lays out each title as its natural (unbounded)
        // text width, so on a category axis with several long names they
        // overlap their neighbors instead of wrapping or truncating.
        final slotWidth = constraints.maxWidth / data.length;
        return _buildBarChart(data, maxValue, slotWidth, currency);
      },
    );
  }

  Widget _buildBarChart(
    List<MapEntry<String, double>> data,
    double maxValue,
    double slotWidth,
    AppCurrency currency,
  ) {
    return BarChart(
      BarChartData(
        maxY: maxValue == 0 ? 1 : maxValue * 1.22,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxValue == 0 ? 1 : maxValue / 2,
          getDrawingHorizontalLine: (value) => FlLine(
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
                  formatMoney(rod.toY, currency),
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
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: slotWidth - 4,
                    child: Text(
                      data[index].key,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted,
                        height: 1.15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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
                            isExpanded: true,
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
                            isExpanded: true,
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
                            isExpanded: true,
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

                // Summary cards - two per metric, one per currency, since
                // there's no toggle anymore to pick just one (see
                // claude.md's "Currencies": never blend USD and SLSH).
                SizedBox(
                  height: 82,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: summary.entries.expand((e) {
                      // "Outstanding" is the headline number — give it
                      // the account's accent; supporting figures stay
                      // neutral.
                      final isHeadline =
                          e.key == 'Outstanding' || e.key.startsWith('Total');
                      final color = isHeadline
                          ? _accountColor
                          : AppColors.inkSecondary;
                      return AppCurrency.values.map((currency) {
                        final value = e.value[currency] ?? 0;
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
                                '${e.key} (${currency.code})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                formatMoney(value, currency),
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
                      });
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: _selectedAccount == 'Expenses'
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            // A category breakdown doesn't make sense once
                            // you've already filtered to one category - it
                            // would otherwise still show the *other*
                            // categories that happen to share a
                            // multi-invoice transaction with the selected
                            // one, which reads as "why are these here?".
                            // A bar chart can't sensibly overlay two
                            // currencies on one axis (see claude.md's
                            // "Currencies"), so each currency that
                            // actually has data gets its own chart card.
                            if (_selectedCategoryName == null) ...[
                              for (final currency in AppCurrency.values)
                                if (_categoryChartData(
                                  currency,
                                ).isNotEmpty) ...[
                                  _chartCard(
                                    title:
                                        'Spending by category (${currency.code})',
                                    subtitle: 'Top categories in this range',
                                    icon: Icons.pie_chart_outline,
                                    chart: _barChart(
                                      _categoryChartData(currency),
                                      currency,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                            ] else ...[
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed: _categoryInvoices.isEmpty
                                      ? null
                                      : () => _openCategoryInvoices(context),
                                  icon: const Icon(
                                    Icons.receipt_long_outlined,
                                    size: 17,
                                  ),
                                  label: Text(
                                    'View ${_categoryInvoices.length} invoice'
                                    '${_categoryInvoices.length == 1 ? '' : 's'}',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            for (final currency in AppCurrency.values)
                              if (_monthlyChartData(currency).isNotEmpty) ...[
                                _chartCard(
                                  title: 'Spending by month (${currency.code})',
                                  subtitle: _selectedCategoryName == null
                                      ? 'Last 6 months with activity'
                                      : '$_selectedCategoryName, last 6 months with activity',
                                  icon: Icons.show_chart,
                                  chart: _barChart(
                                    _monthlyChartData(currency),
                                    currency,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
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
                            final rowCurrency = AppCurrency.fromCode(
                              t['currency'] as String?,
                            );
                            final amount = _selectedAccount == 'Expenses'
                                ? _expenseAmountFor(t)
                                : (t['amount'] as num).toDouble();
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
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _dateFormat.format(date),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    isNeutral
                                        ? formatMoney(amount, rowCurrency)
                                        : '${isIn ? '+' : '-'}${formatMoney(amount, rowCurrency)}',
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
