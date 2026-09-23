import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'add_harvest_screen.dart';
import 'harvest_detail_screen.dart';

/// Every harvest logged, newest first, with summary stats (how many
/// harvests, total kg, total sale value, how much of that has been
/// collected). A harvest is pure inventory intake - see
/// add_harvest_screen.dart - and can be sold to more than one customer
/// over time via harvest_detail_screen.dart. Value/outstanding are
/// tracked per currency - never blended.
class HarvestsScreen extends StatefulWidget {
  const HarvestsScreen({super.key});

  @override
  State<HarvestsScreen> createState() => _HarvestsScreenState();
}

class _HarvestsScreenState extends State<HarvestsScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _harvests = [];

  /// harvestId -> total kg sold across all sales against it.
  Map<String, double> _soldByHarvest = {};

  /// harvestId -> total fee-adjusted sale value, per currency.
  Map<String, Map<AppCurrency, double>> _valueByHarvest = {};
  Map<AppCurrency, double> _totalValueByCurrency = {};
  Map<AppCurrency, double> _paidTotals = {};
  String? _role;

  final _dateFormat = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    _loadRole();
    _load();
  }

  Future<void> _loadRole() async {
    final userId = supabase.auth.currentUser!.id;
    final profile = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .single();
    if (mounted) setState(() => _role = profile['role'] as String?);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final harvestsData = await supabase
          .from('harvests')
          .select()
          .order('harvest_date', ascending: false);

      final salesData = await supabase
          .from('harvest_sales')
          .select('harvest_id, kg_sold, price_per_kg, transport_fee, currency');
      final sales = List<Map<String, dynamic>>.from(salesData);

      final soldByHarvest = <String, double>{};
      final valueByHarvest = <String, Map<AppCurrency, double>>{};
      final totalValue = {for (final c in AppCurrency.values) c: 0.0};
      for (final s in sales) {
        final harvestId = s['harvest_id'] as String;
        final kg = (s['kg_sold'] as num).toDouble();
        soldByHarvest[harvestId] = (soldByHarvest[harvestId] ?? 0) + kg;
        final currency = AppCurrency.fromCode(s['currency'] as String?);
        final transportFee = (s['transport_fee'] as num? ?? 0).toDouble();
        final value = kg * (s['price_per_kg'] as num).toDouble() - transportFee;
        totalValue[currency] = (totalValue[currency] ?? 0) + value;
        final harvestValues =
            valueByHarvest[harvestId] ??
            {for (final c in AppCurrency.values) c: 0.0};
        harvestValues[currency] = (harvestValues[currency] ?? 0) + value;
        valueByHarvest[harvestId] = harvestValues;
      }

      final paymentsData = await supabase
          .from('customer_payments')
          .select('amount, currency');
      final paidTotals = {for (final c in AppCurrency.values) c: 0.0};
      for (final p in List<Map<String, dynamic>>.from(paymentsData)) {
        final currency = AppCurrency.fromCode(p['currency'] as String?);
        paidTotals[currency] =
            (paidTotals[currency] ?? 0) + (p['amount'] as num).toDouble();
      }

      setState(() {
        _harvests = List<Map<String, dynamic>>.from(harvestsData);
        _soldByHarvest = soldByHarvest;
        _valueByHarvest = valueByHarvest;
        _totalValueByCurrency = totalValue;
        _paidTotals = paidTotals;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load harvests: $e';
        _loading = false;
      });
    }
  }

  double get _totalKg => _harvests.fold(
    0,
    (sum, h) => sum + (h['kg_harvested'] as num).toDouble(),
  );

  double get _totalKgSold =>
      _soldByHarvest.values.fold(0, (sum, kg) => sum + kg);

  double get _totalKgRemaining =>
      (_totalKg - _totalKgSold).clamp(0.0, double.infinity);

  Map<AppCurrency, double> get _totalOutstandingByCurrency => {
    for (final c in AppCurrency.values)
      c: (_totalValueByCurrency[c] ?? 0) - (_paidTotals[c] ?? 0),
  };

  Future<void> _openAddHarvest() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddHarvestScreen()));
    if (result == true) _load();
  }

  Future<void> _openHarvest(Map<String, dynamic> h) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HarvestDetailScreen(
          harvestId: h['id'] as String,
          harvestNumber: h['harvest_number'] as int,
          harvestDate: DateTime.parse(h['harvest_date'] as String),
          kgHarvested: (h['kg_harvested'] as num).toDouble(),
          note: h['note'] as String?,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Harvests')),
      floatingActionButton: _role == 'admin'
          ? FloatingActionButton.extended(
              onPressed: _openAddHarvest,
              icon: const Icon(Icons.add, size: 22),
              label: const Text(
                'Harvest',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: ErrorNote(_errorMessage!)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.eco_outlined,
                          label: 'Total harvests',
                          valueWidget: _StatValueWithSub(
                            value: '${_harvests.length}',
                            sub: '(${_totalKg.toStringAsFixed(1)} kg)',
                          ),
                          color: AppColors.brandGreenLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          icon: Icons.scale_outlined,
                          label: 'Total kg sold',
                          valueWidget: _StatValueWithSub(
                            value: _totalKgSold.toStringAsFixed(1),
                            sub:
                                '(${_totalKgRemaining.toStringAsFixed(1)} kg left)',
                          ),
                          color: AppColors.brandGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppCard(
                          accent: AppColors.cashIn,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IconBadge(
                                icon: Icons.attach_money,
                                color: AppColors.cashIn,
                                size: 34,
                                iconSize: 17,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Total sold',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSecondary,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 3),
                              DualCurrencyStat(
                                amounts: _totalValueByCurrency,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppCard(
                          accent: AppColors.expense,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IconBadge(
                                icon: Icons.pending_outlined,
                                color: AppColors.expense,
                                size: 34,
                                iconSize: 17,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Total outstanding',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSecondary,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 3),
                              DualCurrencyStat(
                                amounts: _totalOutstandingByCurrency,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const SectionLabel('ALL HARVESTS'),
                  const SizedBox(height: 10),
                  if (_harvests.isEmpty)
                    const EmptyState(
                      icon: Icons.eco_outlined,
                      title: 'No harvests logged yet',
                      subtitle: 'Tap "Harvest" to record your first one.',
                    )
                  else
                    ..._harvests.map((h) {
                      final kg = (h['kg_harvested'] as num).toDouble();
                      final sold = _soldByHarvest[h['id']] ?? 0;
                      final remaining = (kg - sold).clamp(0, double.infinity);
                      final fullySold = remaining <= 0.01;
                      final date = DateTime.parse(h['harvest_date'] as String);
                      final value =
                          _valueByHarvest[h['id']] ??
                          {for (final c in AppCurrency.values) c: 0.0};
                      final hasValue = value.values.any((v) => v > 0.001);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          onTap: () => _openHarvest(h),
                          child: Row(
                            children: [
                              IconBadge(
                                icon: Icons.eco_outlined,
                                color: fullySold
                                    ? AppColors.neutral
                                    : AppColors.brandGreenLight,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '#H${h['harvest_number']} · ${_dateFormat.format(date)}',
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${kg.toStringAsFixed(1)} kg harvested · '
                                      '${sold.toStringAsFixed(1)} kg sold',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    fullySold
                                        ? 'Fully sold'
                                        : '${remaining.toStringAsFixed(1)} kg left',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: fullySold
                                          ? AppColors.inkMuted
                                          : AppColors.cashIn,
                                    ),
                                  ),
                                  if (hasValue) ...[
                                    const SizedBox(height: 3),
                                    DualCurrencyStat(
                                      amounts: value,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.brandGreenDeep,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

/// A StatTile value with a smaller parenthetical line underneath (e.g.
/// harvest count with total kg, or kg sold with kg remaining).
class _StatValueWithSub extends StatelessWidget {
  const _StatValueWithSub({required this.value, required this.sub});

  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            letterSpacing: -0.3,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
