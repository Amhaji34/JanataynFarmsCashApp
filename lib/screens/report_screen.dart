import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'account_records_screen.dart';
import 'category_invoices_screen.dart';

enum _ProfitMode { cashFlow, profit }

/// "Both" shows every currency side by side exactly as the rest of the
/// app does (see claude.md's "Currencies": never blend USD and SLSH).
/// Picking USD/SLSH instead collapses every figure on this screen into
/// that one currency using the admin-entered exchange rate - a
/// deliberate, visible exception scoped to this screen only, the
/// reporting counterpart of exchange_screen.dart's "Currency exchange"
/// exception (see claude.md).
enum _CurrencyDisplayMode { both, usdOnly, slshOnly }

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
  static const _accounts = [
    'Expenses',
    'Profit',
    'Advances',
    'Payroll',
    'Loans',
  ];

  late String _selectedAccount = widget.initialAccount ?? 'Expenses';

  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _categories = [];

  /// `fund_add` rows only (account_transactions), joined to the
  /// account's name - the "money coming in" side of the Profit tab.
  /// Fetched separately from `_transactions` since it's a different
  /// table (see claude.md's "Funding accounts").
  List<Map<String, dynamic>> _fundAdds = [];

  String? _selectedStaffId;
  String? _selectedPartnerId;
  String? _selectedCategoryName;
  late DateTimeRange? _dateRange = widget.initialDateRange;

  /// Cash Flow counts every dollar in/out including capital and loans;
  /// Profit counts only harvest-sale revenue against operating costs -
  /// see the Profit tab's `_summary` case and its explanatory caption.
  _ProfitMode _profitMode = _ProfitMode.cashFlow;

  /// "Currency display" section state - see `_CurrencyDisplayMode`.
  /// The rate is 1 USD in SLSH, matching how a money changer would quote
  /// it; not persisted anywhere (same "no stored exchange rate" stance
  /// as exchange_screen.dart - it's re-entered per session/visit).
  _CurrencyDisplayMode _displayMode = _CurrencyDisplayMode.both;
  double _exchangeRate = 11000;
  late final _rateController = TextEditingController(
    text: _exchangeRate.toStringAsFixed(0),
  );

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

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
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
      final fundAdds = await supabase
          .from('account_transactions')
          .select(
            'amount, currency, transaction_date, '
            'accounts!account_transactions_account_id_fkey(name)',
          )
          .eq('type', 'fund_add');

      setState(() {
        _transactions = List<Map<String, dynamic>>.from(txns);
        _staff = List<Map<String, dynamic>>.from(staff);
        _partners = List<Map<String, dynamic>>.from(partners);
        _categories = List<Map<String, dynamic>>.from(categories);
        _fundAdds = List<Map<String, dynamic>>.from(fundAdds);
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

  /// The "headline" gross amount a transaction contributes to the
  /// current tab's charts - the counterpart type (advance_deduction,
  /// loan_repayment) contributes 0, so the breakdown/monthly charts read
  /// as "money given/paid out", not a net that can dip negative.
  double _headlineAmountFor(Map<String, dynamic> t) {
    switch (_selectedAccount) {
      case 'Payroll':
        return (t['amount'] as num).toDouble();
      case 'Advances':
        return t['type'] == 'advance' ? (t['amount'] as num).toDouble() : 0;
      case 'Loans':
        return t['type'] == 'loan' ? (t['amount'] as num).toDouble() : 0;
      case 'Expenses':
        return _expenseAmountFor(t);
      default:
        return 0;
    }
  }

  Map<AppCurrency, double> _zeroByCurrency() => {
    for (final c in AppCurrency.values) c: 0.0,
  };

  /// Which currencies this screen currently renders - both, in "Both"
  /// mode, or just the one chosen in the "Currency display" section.
  /// Every per-currency chart/card loop iterates this instead of
  /// `AppCurrency.values` directly.
  List<AppCurrency> get _displayCurrencies => switch (_displayMode) {
    _CurrencyDisplayMode.both => AppCurrency.values,
    _CurrencyDisplayMode.usdOnly => [AppCurrency.usd],
    _CurrencyDisplayMode.slshOnly => [AppCurrency.slsh],
  };

  /// Converts one amount from its native currency into `to` using the
  /// admin-entered exchange rate (1 USD = `_exchangeRate` SLSH) - a
  /// no-op when they're already the same currency. Only ever called
  /// outside "Both" mode; "Both" mode never converts (see claude.md's
  /// "Currencies": never blend without an explicit, visible rate).
  double _convert(double amount, AppCurrency from, AppCurrency to) {
    if (from == to) return amount;
    return to == AppCurrency.slsh
        ? amount * _exchangeRate
        : amount / _exchangeRate;
  }

  /// An amount's value in `target`: itself if `_displayMode` is "Both"
  /// (or already native), converted otherwise. Centralizes the
  /// "Both mode never converts, single-currency mode always does" rule
  /// every chart/card/list data getter below applies.
  double _displayAmount(double amount, AppCurrency native, AppCurrency target) {
    if (_displayMode == _CurrencyDisplayMode.both) return amount;
    return _convert(amount, native, target);
  }

  /// Collapses a per-(native)-currency map - e.g. one `_summary` entry -
  /// into the single currently-selected display currency, converting and
  /// summing both currencies' contributions. Only meaningful outside
  /// "Both" mode; the summary card loop only calls this then.
  double _collapseToDisplay(Map<AppCurrency, double> byCurrency) {
    final target = _displayCurrencies.single;
    return byCurrency.entries.fold<double>(
      0,
      (sum, e) => sum + _convert(e.value, e.key, target),
    );
  }

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

  /// Income broken down by where it came from, for one currency, sorted
  /// descending, zero entries dropped - the Profit tab's statement table
  /// groups Cash Flow's `fund_add` rows by their account name (Revenue's
  /// "Harvest sales" is the only source Profit mode keeps) and adds a
  /// "Loan repayments" line in Cash Flow mode only. `_profitIncome`
  /// below sums this list rather than duplicating the filtering logic.
  List<MapEntry<String, double>> _profitIncomeBreakdown(AppCurrency currency) {
    final totals = <String, double>{};
    for (final f in _fundAdds) {
      if (!_matchesDate(f)) continue;
      final native = AppCurrency.fromCode(f['currency'] as String?);
      if (_displayMode == _CurrencyDisplayMode.both && native != currency) {
        continue;
      }
      final accountName = f['accounts']?['name'] as String?;
      if (_profitMode == _ProfitMode.profit && accountName != 'Revenue') {
        continue;
      }
      final label = switch (accountName) {
        'Revenue' => 'Harvest sales',
        'Investment' => 'Investment',
        'Loans' => 'Loan proceeds',
        _ => accountName ?? 'Other',
      };
      final amount = _displayAmount(
        (f['amount'] as num).toDouble(),
        native,
        currency,
      );
      totals[label] = (totals[label] ?? 0) + amount;
    }
    if (_profitMode == _ProfitMode.cashFlow) {
      for (final t in _transactions) {
        if (t['type'] != 'loan_repayment' || !_matchesDate(t)) continue;
        final native = AppCurrency.fromCode(t['currency'] as String?);
        if (_displayMode == _CurrencyDisplayMode.both && native != currency) {
          continue;
        }
        final amount = _displayAmount(
          (t['amount'] as num).toDouble(),
          native,
          currency,
        );
        totals['Loan repayments'] = (totals['Loan repayments'] ?? 0) + amount;
      }
    }
    return totals.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Outgoing broken down by type, for one currency, sorted descending,
  /// zero entries dropped. Deliberately doesn't split Expenses by
  /// category the way the Expenses tab's own chart does - this table is
  /// about where cash goes at the type level (expenses vs. payroll vs.
  /// loans/advances given), not a category audit.
  List<MapEntry<String, double>> _profitOutgoingBreakdown(
    AppCurrency currency,
  ) {
    final totals = <String, double>{};
    const labels = {
      'expense': 'Expenses',
      'payroll': 'Payroll',
      'loan': 'Loans given',
      'advance': 'Advances given',
    };
    const cashFlowTypes = {'expense', 'payroll', 'loan', 'advance'};
    const profitTypes = {'expense', 'payroll'};
    final types = _profitMode == _ProfitMode.cashFlow
        ? cashFlowTypes
        : profitTypes;
    for (final t in _transactions) {
      if (!types.contains(t['type']) || !_matchesDate(t)) continue;
      final native = AppCurrency.fromCode(t['currency'] as String?);
      if (_displayMode == _CurrencyDisplayMode.both && native != currency) {
        continue;
      }
      final label = labels[t['type']]!;
      final amount = _displayAmount(
        (t['amount'] as num).toDouble(),
        native,
        currency,
      );
      totals[label] = (totals[label] ?? 0) + amount;
    }
    return totals.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Spend per category for one currency, sorted descending - every
  /// category, not capped, since the chart itself scrolls horizontally
  /// once there isn't room to fit them all (see `_barChart`). A bar
  /// chart can't sensibly overlay two currencies on one axis, so this
  /// renders as one chart card per currency that actually has data -
  /// see the build method.
  List<MapEntry<String, double>> _categoryChartData(AppCurrency currency) {
    final totals = <String, double>{};
    for (final t in _filtered) {
      final native = AppCurrency.fromCode(t['currency'] as String?);
      if (_displayMode == _CurrencyDisplayMode.both && native != currency) {
        continue;
      }
      for (final item in _itemsOf(t)) {
        final category = item['category'] as String? ?? '';
        if (category.isEmpty) continue;
        final amount = _displayAmount(
          (item['amount'] as num).toDouble(),
          native,
          currency,
        );
        totals[category] = (totals[category] ?? 0) + amount;
      }
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Which name field the breakdown chart groups by - staff for
  /// Payroll/Advances, partner for Loans. Not used for Expenses, which
  /// has its own category breakdown.
  String? _breakdownNameFor(Map<String, dynamic> t) {
    switch (_selectedAccount) {
      case 'Payroll':
      case 'Advances':
        return t['staff']?['name'] as String?;
      case 'Loans':
        return t['partners']?['name'] as String?;
      default:
        return null;
    }
  }

  /// "staff"/"partner" - used in the chart's subtitle and to decide
  /// whether the breakdown chart is redundant with the staff/partner
  /// filter already selected (same reasoning as Expenses hiding its
  /// category chart once a category is picked).
  String get _breakdownDimensionLabel =>
      _selectedAccount == 'Loans' ? 'partner' : 'staff';

  bool get _breakdownAlreadyFiltered => _selectedAccount == 'Loans'
      ? _selectedPartnerId != null
      : _selectedStaffId != null;

  /// The headline gross amount broken down by staff/partner for one
  /// currency, sorted descending - the Payroll/Advances/Loans
  /// counterpart of `_categoryChartData`, same "every entry, chart
  /// scrolls if needed" shape.
  List<MapEntry<String, double>> _breakdownChartData(AppCurrency currency) {
    final totals = <String, double>{};
    for (final t in _filtered) {
      final native = AppCurrency.fromCode(t['currency'] as String?);
      if (_displayMode == _CurrencyDisplayMode.both && native != currency) {
        continue;
      }
      final rawAmount = _headlineAmountFor(t);
      if (rawAmount <= 0) continue;
      final name = _breakdownNameFor(t);
      if (name == null || name.isEmpty) continue;
      final amount = _displayAmount(rawAmount, native, currency);
      totals[name] = (totals[name] ?? 0) + amount;
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Every currently filtered transaction, as an AccountRecord -
  /// AccountRecordsScreen's "View N records" list. Used by
  /// Payroll/Advances/Loans (Expenses has its own, narrower
  /// category_invoices_screen.dart flow instead).
  List<AccountRecord> get _accountRecords {
    return _filtered.map((t) {
      final type = t['type'] as String;
      final isIn = _isCashIn(type);
      final isNeutral = _isNeutral(type);
      final native = AppCurrency.fromCode(t['currency'] as String?);
      final displayCurrency = _displayMode == _CurrencyDisplayMode.both
          ? native
          : _displayCurrencies.single;
      return AccountRecord(
        title: _rowTitle(t),
        date: DateTime.parse(t['transaction_date'] as String),
        amount: _displayAmount(
          (t['amount'] as num).toDouble(),
          native,
          displayCurrency,
        ),
        currency: displayCurrency,
        color: _rowColor(t),
        icon: isIn
            ? Icons.south_west
            : isNeutral
            ? Icons.sync_alt
            : _accountIcon,
        isPositive: isIn,
        isNeutral: isNeutral,
        note: (t['note'] as String? ?? '').trim(),
      );
    }).toList();
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
      final native = AppCurrency.fromCode(t['currency'] as String?);
      final displayCurrency = _displayMode == _CurrencyDisplayMode.both
          ? native
          : _displayCurrencies.single;
      for (final item in matching) {
        invoices.add(
          CategoryInvoice(
            transactionId: t['id'] as String,
            itemId: item['id'] as String,
            date: DateTime.parse(t['transaction_date'] as String),
            amount: _displayAmount(
              (item['amount'] as num).toDouble(),
              native,
              displayCurrency,
            ),
            currency: displayCurrency,
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

  /// Headline amount per month for one currency, chronological, capped
  /// to the most recent 6 months present in the filtered data. Shared by
  /// all four tabs via `_headlineAmountFor`.
  List<MapEntry<String, double>> _monthlyChartData(AppCurrency currency) {
    final totals = <DateTime, double>{};
    for (final t in _filtered) {
      final native = AppCurrency.fromCode(t['currency'] as String?);
      if (_displayMode == _CurrencyDisplayMode.both && native != currency) {
        continue;
      }
      final date = DateTime.parse(t['transaction_date'] as String);
      final key = DateTime(date.year, date.month);
      final amount = _displayAmount(_headlineAmountFor(t), native, currency);
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
      case 'Profit':
        return AppColors.cashIn;
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

  void _openAccountRecords(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountRecordsScreen(
          accountName: _selectedAccount,
          records: _accountRecords,
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
      case 'Profit':
        return Icons.trending_up;
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

  /// Which dropdown item `_dateRange` currently corresponds to - 'all'
  /// for no filter, 'this_month' when it's exactly the current calendar
  /// month (including a dashboard deep-link's `initialDateRange`, which
  /// is always the current month), or 'custom' for anything else
  /// (a hand-picked range, or a past/future month picked as a custom
  /// range).
  String get _dateFilterKey {
    if (_dateRange == null) return 'all';
    final now = DateTime.now();
    final s = _dateRange!.start;
    final e = _dateRange!.end;
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final isCurrentMonth =
        s.year == now.year &&
        s.month == now.month &&
        s.day == 1 &&
        e.year == lastDayOfMonth.year &&
        e.month == lastDayOfMonth.month &&
        e.day == lastDayOfMonth.day;
    return isCurrentMonth ? 'this_month' : 'custom';
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

    // Every bar gets at least this much width - below it, labels and
    // bars start crowding each other regardless of how few characters
    // the label wraps to. Past a certain number of entries this makes
    // the chart wider than the card, so it scrolls horizontally instead
    // of squeezing every bar into the same fixed width.
    const minSlotWidth = 56.0;
    // A touched bar's tooltip bubble is centered over it and can be
    // wider than half a slot - without this padding, the leftmost (or
    // rightmost) bar's tooltip renders partly past the scrollable
    // content's edge and gets clipped there by SingleChildScrollView,
    // instead of just floating past the visible viewport like it does
    // for every other bar.
    const chartPadding = 28.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - chartPadding * 2;
        final barsWidth = data.length * minSlotWidth > availableWidth
            ? data.length * minSlotWidth
            : availableWidth;
        // Each label gets boxed to its own bar's slot width - without
        // this, fl_chart lays out each title as its natural (unbounded)
        // text width, so on a category axis with several long names they
        // overlap their neighbors instead of wrapping or truncating.
        final slotWidth = barsWidth / data.length;
        final chart = Padding(
          padding: const EdgeInsets.symmetric(horizontal: chartPadding),
          child: SizedBox(
            width: barsWidth,
            child: _buildBarChart(data, maxValue, slotWidth, currency),
          ),
        );
        if (barsWidth <= availableWidth) return chart;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: chart,
        );
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
            // Without these, fl_chart centers a touched bar's tooltip
            // blindly and lets it overflow past the chart's own edges -
            // for the first/last bar that overflow gets clipped by
            // whichever scrollable ancestor contains the chart, showing
            // up as an empty box with no visible value. These shift the
            // tooltip back inside the chart's bounds instead.
            fitInsideHorizontally: true,
            fitInsideVertically: true,
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

  /// An income-statement-style card for one currency: an Income section
  /// (harvest sales, and in Cash Flow mode also investment/loan
  /// proceeds/repayments), an Outgoing section (expenses and payroll,
  /// plus loans/advances given in Cash Flow mode - expenses aren't split
  /// by category here, unlike the Expenses tab's own chart, since this
  /// table is about income vs. outgoing at the type level), then Total
  /// income, Total outgoing, and Net at the bottom - the Investopedia-
  /// style layout the user asked to match, minus a separate tax line
  /// (this app has no tax concept of its own; a "Tax" expense category
  /// just folds into the single "Expenses" row like every other
  /// category).
  Widget _profitStatementCard(AppCurrency currency) {
    final income = _profitIncomeBreakdown(currency);
    final outgoing = _profitOutgoingBreakdown(currency);
    final totalIncome = income.fold<double>(0, (sum, e) => sum + e.value);
    final totalOutgoing = outgoing.fold<double>(0, (sum, e) => sum + e.value);
    final net = totalIncome - totalOutgoing;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_profitMode == _ProfitMode.cashFlow ? 'Cash Flow' : 'Profit'} '
            '(${currency.code})',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          _statementSectionHeader('Income'),
          if (income.isEmpty)
            _statementRow('No income', 0, currency)
          else
            for (final e in income) _statementRow(e.key, e.value, currency),
          _statementDivider(),
          _statementRow('Total income', totalIncome, currency, bold: true),
          const SizedBox(height: 16),
          _statementSectionHeader('Outgoing'),
          if (outgoing.isEmpty)
            _statementRow('No outgoing', 0, currency)
          else
            for (final e in outgoing) _statementRow(e.key, e.value, currency),
          _statementDivider(),
          _statementRow('Total outgoing', totalOutgoing, currency, bold: true),
          const SizedBox(height: 6),
          _statementDivider(),
          _statementRow(
            'Net',
            net,
            currency,
            bold: true,
            color: net < 0 ? AppColors.expense : AppColors.cashIn,
          ),
        ],
      ),
    );
  }

  Widget _statementSectionHeader(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AppColors.inkSecondary,
      ),
    ),
  );

  Widget _statementDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Divider(height: 1, color: AppColors.hairline),
  );

  Widget _statementRow(
    String label,
    double amount,
    AppCurrency currency, {
    bool bold = false,
    Color? color,
  }) {
    final textColor = color ?? (bold ? AppColors.ink : AppColors.inkSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? AppColors.ink : AppColors.inkSecondary,
            ),
          ),
          Text(
            formatMoney(amount, currency),
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: textColor,
            ),
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
                        'Profit' => AppColors.cashIn,
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

                // Filters - the contextual dropdown (staff/partner/
                // category) and the date range each get their own full-
                // width row, stacked, rather than squeezed side by side -
                // a picked date range's label is long enough that sharing
                // a row left neither one enough space.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_selectedAccount == 'Payroll' ||
                          _selectedAccount == 'Advances')
                        Row(
                          children: [
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
                            if (_selectedStaffId != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                color: AppColors.inkMuted,
                                onPressed: () =>
                                    setState(() => _selectedStaffId = null),
                              ),
                          ],
                        ),
                      if (_selectedAccount == 'Loans')
                        Row(
                          children: [
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
                            if (_selectedPartnerId != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                color: AppColors.inkMuted,
                                onPressed: () =>
                                    setState(() => _selectedPartnerId = null),
                              ),
                          ],
                        ),
                      if (_selectedAccount == 'Expenses')
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedCategoryName,
                                decoration: _dropdownDecoration(
                                  'All categories',
                                ),
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
                                onChanged: (value) => setState(
                                  () => _selectedCategoryName = value,
                                ),
                              ),
                            ),
                            if (_selectedCategoryName != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                color: AppColors.inkMuted,
                                onPressed: () => setState(
                                  () => _selectedCategoryName = null,
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _dateFilterKey,
                        decoration: _dropdownDecoration('Date range'),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All time'),
                          ),
                          const DropdownMenuItem(
                            value: 'this_month',
                            child: Text('This month'),
                          ),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text(
                              _dateFilterKey == 'custom' && _dateRange != null
                                  ? '${_dateFormat.format(_dateRange!.start)} - ${_dateFormat.format(_dateRange!.end)}'
                                  : 'Custom range',
                            ),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value == 'all') {
                            setState(() => _dateRange = null);
                          } else if (value == 'this_month') {
                            final now = DateTime.now();
                            setState(
                              () => _dateRange = DateTimeRange(
                                start: DateTime(now.year, now.month, 1),
                                end: DateTime(now.year, now.month + 1, 0),
                              ),
                            );
                          } else {
                            await _pickDateRange();
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // Currency display - "Both" (default) shows every chart/
                // card as USD and SLSH side by side, exactly as the rest
                // of the app does; picking USD or SLSH instead collapses
                // every figure on this screen into that one currency
                // using the rate entered below. Applies to every tab, not
                // just Profit.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Currency display',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _CurrencyDisplayModeToggle(
                          value: _displayMode,
                          onChanged: (mode) =>
                              setState(() => _displayMode = mode),
                        ),
                        if (_displayMode != _CurrencyDisplayMode.both) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                '1 USD =',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _rateController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _dropdownDecoration(
                                    '11000',
                                  ).copyWith(suffixText: 'SLSH'),
                                  onChanged: (value) {
                                    final parsed = double.tryParse(
                                      value.trim(),
                                    );
                                    if (parsed != null && parsed > 0) {
                                      setState(() => _exchangeRate = parsed);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                if (_selectedAccount == 'Profit')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _ProfitModeToggle(
                      value: _profitMode,
                      onChanged: (mode) => setState(() => _profitMode = mode),
                    ),
                  ),

                // Summary cards - two per metric, one per currency, since
                // there's no toggle anymore to pick just one (see
                // claude.md's "Currencies": never blend USD and SLSH).
                // Skipped for Profit, whose statement table (built into
                // the body below) already carries these totals plus a
                // full income/outgoing breakdown.
                if (_selectedAccount != 'Profit') ...[
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
                        return _displayCurrencies.map((currency) {
                          final value =
                              _displayMode == _CurrencyDisplayMode.both
                              ? (e.value[currency] ?? 0)
                              : _collapseToDisplay(e.value);
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
                ],

                Expanded(
                  child: (_selectedAccount != 'Profit' && filtered.isEmpty)
                      ? EmptyState(
                          icon: _accountIcon,
                          title: 'Nothing to report yet',
                          subtitle:
                              'No $_selectedAccount records match these '
                              'filters.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            if (_selectedAccount == 'Profit') ...[
                              Text(
                                _profitMode == _ProfitMode.cashFlow
                                    ? 'Every dollar in and out of the '
                                          'business: harvest revenue, capital '
                                          'investment, loan proceeds, and loan '
                                          'repayments count as income; '
                                          'expenses, payroll, loans given, and '
                                          'advances given count as outgoing.'
                                    : 'Only harvest-sale revenue counts as '
                                          'income; only expenses and payroll '
                                          'count as outgoing. Capital, loans, '
                                          'and advances are excluded - they\'re '
                                          'owed back, not earnings or costs.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_displayCurrencies.every(
                                (c) =>
                                    _profitIncomeBreakdown(c).isEmpty &&
                                    _profitOutgoingBreakdown(c).isEmpty,
                              ))
                                EmptyState(
                                  icon: _accountIcon,
                                  title: 'Nothing to report yet',
                                  subtitle:
                                      'No income or outgoing in this range.',
                                )
                              else
                                for (final currency in _displayCurrencies)
                                  if (_profitIncomeBreakdown(
                                        currency,
                                      ).isNotEmpty ||
                                      _profitOutgoingBreakdown(
                                        currency,
                                      ).isNotEmpty) ...[
                                    _profitStatementCard(currency),
                                    const SizedBox(height: 12),
                                  ],
                            ] else if (_selectedAccount == 'Expenses') ...[
                              // A category breakdown doesn't make sense
                              // once you've already filtered to one
                              // category - it would otherwise still show
                              // the *other* categories that happen to
                              // share a multi-invoice transaction with
                              // the selected one, which reads as "why are
                              // these here?". A bar chart can't sensibly
                              // overlay two currencies on one axis (see
                              // claude.md's "Currencies"), so each
                              // currency that actually has data gets its
                              // own chart card.
                              if (_selectedCategoryName == null) ...[
                                for (final currency in _displayCurrencies)
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
                            ] else ...[
                              // Same reasoning as the Expenses category
                              // chart above: a breakdown by staff/partner
                              // is redundant once you've already filtered
                              // to one of them.
                              if (!_breakdownAlreadyFiltered) ...[
                                for (final currency in _displayCurrencies)
                                  if (_breakdownChartData(
                                    currency,
                                  ).isNotEmpty) ...[
                                    _chartCard(
                                      title:
                                          '$_selectedAccount by $_breakdownDimensionLabel (${currency.code})',
                                      subtitle:
                                          'Top $_breakdownDimensionLabel in this range',
                                      icon: Icons.bar_chart_outlined,
                                      chart: _barChart(
                                        _breakdownChartData(currency),
                                        currency,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                              ],
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openAccountRecords(context),
                                  icon: const Icon(
                                    Icons.receipt_long_outlined,
                                    size: 17,
                                  ),
                                  label: Text(
                                    'View ${filtered.length} record'
                                    '${filtered.length == 1 ? '' : 's'}',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            for (final currency in _displayCurrencies)
                              if (_monthlyChartData(currency).isNotEmpty) ...[
                                _chartCard(
                                  title:
                                      '$_selectedAccount by month (${currency.code})',
                                  subtitle: _selectedAccount == 'Expenses'
                                      ? (_selectedCategoryName == null
                                            ? 'Last 6 months with activity'
                                            : '$_selectedCategoryName, last 6 months with activity')
                                      : 'Last 6 months with activity',
                                  icon: Icons.show_chart,
                                  chart: _barChart(
                                    _monthlyChartData(currency),
                                    currency,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

/// Two-segment Cash Flow/Profit pill, matching CurrencyToggle's visual
/// style (lib/utils/currency.dart) - see the Profit tab's `_summary`
/// case for what each mode actually counts.
class _ProfitModeToggle extends StatelessWidget {
  const _ProfitModeToggle({required this.value, required this.onChanged});

  final _ProfitMode value;
  final ValueChanged<_ProfitMode> onChanged;

  static const _options = [
    (_ProfitMode.cashFlow, 'Cash Flow'),
    (_ProfitMode.profit, 'Profit'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (mode, label) in _options) ...[
          if (mode != _options.first.$1) const SizedBox(width: 10),
          Expanded(child: _segment(mode, label)),
        ],
      ],
    );
  }

  Widget _segment(_ProfitMode mode, String label) {
    final selected = mode == value;
    return Material(
      color: selected
          ? AppColors.brandGreen.withValues(alpha: 0.10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusField),
      child: InkWell(
        onTap: () => onChanged(mode),
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
            border: Border.all(
              color: selected
                  ? AppColors.brandGreen.withValues(alpha: 0.45)
                  : AppColors.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.brandGreen : AppColors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three-segment USD/SLSH/Both pill, same visual language as
/// CurrencyToggle/_ProfitModeToggle - see `_CurrencyDisplayMode` for what
/// each option does.
class _CurrencyDisplayModeToggle extends StatelessWidget {
  const _CurrencyDisplayModeToggle({
    required this.value,
    required this.onChanged,
  });

  final _CurrencyDisplayMode value;
  final ValueChanged<_CurrencyDisplayMode> onChanged;

  static const _options = [
    (_CurrencyDisplayMode.usdOnly, 'USD'),
    (_CurrencyDisplayMode.slshOnly, 'SLSH'),
    (_CurrencyDisplayMode.both, 'Both'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (mode, label) in _options) ...[
          if (mode != _options.first.$1) const SizedBox(width: 8),
          Expanded(child: _segment(mode, label)),
        ],
      ],
    );
  }

  Widget _segment(_CurrencyDisplayMode mode, String label) {
    final selected = mode == value;
    return Material(
      color: selected
          ? AppColors.brandGreen.withValues(alpha: 0.10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusField),
      child: InkWell(
        onTap: () => onChanged(mode),
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
            border: Border.all(
              color: selected
                  ? AppColors.brandGreen.withValues(alpha: 0.45)
                  : AppColors.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.brandGreen : AppColors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
