import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Per-staff working state for one payroll run.
class _PayrollLine {
  _PayrollLine({
    required this.staffId,
    required this.name,
    required this.baseSalary,
  }) : repayController = TextEditingController(text: '0.00');

  final String staffId;
  final String name;
  final double baseSalary;

  /// Outstanding advance balance (sum(advance) - sum(advance_deduction)),
  /// fetched once when the screen loads.
  double owed = 0;
  bool loadingOwed = true;

  /// Whether this staff member is part of the current payroll run.
  bool included = true;

  final TextEditingController repayController;

  double get repayAmount => double.tryParse(repayController.text) ?? 0;
  double get netAmount => (baseSalary - repayAmount).clamp(0, double.infinity);

  void dispose() => repayController.dispose();
}

/// Batch payroll: pay some or all staff in one run instead of one
/// transaction at a time. Keeps the same per-staff mechanics the old
/// Add Transaction "payroll" type had (base salary / owed advance /
/// repay amount / net to receive) - just applied to every included staff
/// member at once, with one shared date for the whole run.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<_PayrollLine> _lines = [];

  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');
  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  bool _saving = false;
  String? _errorBanner;

  int get _includedCount => _lines.where((l) => l.included).length;
  double get _totalToPay =>
      _lines.where((l) => l.included).fold(0, (sum, l) => sum + l.netAmount);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final staffData = await supabase.from('staff').select().order('name');
      final staff = List<Map<String, dynamic>>.from(staffData);

      final lines = staff
          .map(
            (s) => _PayrollLine(
              staffId: s['id'] as String,
              name: s['name'] as String,
              baseSalary: (s['base_salary'] as num).toDouble(),
            ),
          )
          .toList();

      setState(() {
        _lines = lines;
        _loading = false;
      });

      // Owed-advance balances load per staff member after the list renders,
      // so the screen doesn't block on N staff x 2 queries up front.
      for (final line in lines) {
        _loadOwed(line);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load staff: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadOwed(_PayrollLine line) async {
    try {
      final advances = await supabase
          .from('transactions')
          .select('amount')
          .eq('type', 'advance')
          .eq('related_staff_id', line.staffId);
      final deductions = await supabase
          .from('transactions')
          .select('amount')
          .eq('type', 'advance_deduction')
          .eq('related_staff_id', line.staffId);

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
        line.owed = advanceTotal - deductionTotal;
        line.loadingOwed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => line.loadingOwed = false);
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

  void _setAllIncluded(bool value) {
    setState(() {
      for (final line in _lines) {
        line.included = value;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _errorBanner = null);

    final toPay = _lines.where((l) => l.included).toList();
    if (toPay.isEmpty) {
      setState(() => _errorBanner = 'Select at least one staff member.');
      return;
    }
    for (final line in toPay) {
      if (line.repayAmount > line.owed + 0.01) {
        setState(
          () => _errorBanner =
              '${line.name}: repay amount can\'t exceed the amount owed '
              '(${_currency.format(line.owed)}).',
        );
        return;
      }
      if (line.repayAmount > line.baseSalary + 0.01) {
        setState(
          () => _errorBanner =
              '${line.name}: repay amount can\'t exceed the base salary.',
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final date = _dbDateFormat.format(_selectedDate);

      for (final line in toPay) {
        final txnResponse = await supabase
            .from('transactions')
            .insert({
              'type': 'payroll',
              'amount': line.netAmount,
              'transaction_date': date,
              'related_staff_id': line.staffId,
              'note': '',
            })
            .select()
            .single();

        await supabase.from('transaction_items').insert({
          'transaction_id': txnResponse['id'],
          'category': 'payroll',
          'amount': line.netAmount,
        });

        if (line.repayAmount > 0) {
          final deductionResponse = await supabase
              .from('transactions')
              .insert({
                'type': 'advance_deduction',
                'amount': line.repayAmount,
                'transaction_date': date,
                'related_staff_id': line.staffId,
                'note': 'Advance deduction for payroll',
              })
              .select()
              .single();

          await supabase.from('transaction_items').insert({
            'transaction_id': deductionResponse['id'],
            'category': 'advance_deduction',
            'amount': line.repayAmount,
          });
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorBanner = 'Could not save payroll: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Run Payroll')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_errorMessage!)),
            )
          : _lines.isEmpty
          ? const EmptyState(
              icon: Icons.people_outline,
              title: 'No staff yet',
              subtitle: 'Add staff members before running payroll.',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('DATE'),
                      const SizedBox(height: 8),
                      Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppStyles.radiusField,
                        ),
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(
                            AppStyles.radiusField,
                          ),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SectionLabel(
                            'STAFF ($_includedCount/${_lines.length})',
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _setAllIncluded(true),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('All'),
                              ),
                              TextButton(
                                onPressed: () => _setAllIncluded(false),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('None'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: _lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _staffCard(_lines[index]),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        if (_errorBanner != null) ...[
                          ErrorNote(_errorBanner!),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 56,
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
                                    _includedCount == 0
                                        ? 'Select staff to pay'
                                        : 'Pay $_includedCount staff · ${_currency.format(_totalToPay)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _staffCard(_PayrollLine line) {
    final included = line.included;

    return AppCard(
      accent: included ? AppColors.payroll : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(name: line.name, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  line.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Switch.adaptive(
                value: included,
                activeTrackColor: AppColors.payroll,
                activeThumbColor: Colors.white,
                onChanged: (value) =>
                    setState(() => line.included = value),
              ),
            ],
          ),
          if (included) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _infoField(
                    'Base salary',
                    _currency.format(line.baseSalary),
                    AppColors.payroll,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _infoField(
                    'Owed (advance)',
                    line.loadingOwed ? '…' : _currency.format(line.owed),
                    AppColors.advance,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'REPAY AMOUNT (DEDUCT FROM SALARY)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: line.repayController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '\$0.00',
                prefixText: '\$ ',
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppStyles.radiusField,
                  ),
                  borderSide: const BorderSide(color: AppColors.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppStyles.radiusField,
                  ),
                  borderSide: const BorderSide(color: AppColors.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppStyles.radiusField,
                  ),
                  borderSide: const BorderSide(
                    color: AppColors.brandGreenLight,
                    width: 1.6,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
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
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: AppColors.brandGreen,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Will receive',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandGreenDeep,
                      ),
                    ),
                  ),
                  Text(
                    _currency.format(line.netAmount),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: AppColors.brandGreenDeep,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoField(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
