import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'add_harvest_screen.dart';

/// Every harvest logged, newest first, with summary stats (how many
/// harvests, total kg, total value, how much of that has been collected).
/// Each harvest doubles as its sale record - see add_harvest_screen.dart.
/// Value/outstanding are tracked per currency - never blended.
class HarvestsScreen extends StatefulWidget {
  const HarvestsScreen({super.key});

  @override
  State<HarvestsScreen> createState() => _HarvestsScreenState();
}

class _HarvestsScreenState extends State<HarvestsScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _harvests = [];
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
          .select('*, customers(name)')
          .order('harvest_date', ascending: false);

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

  Map<AppCurrency, double> get _totalValueByCurrency {
    final totals = {for (final c in AppCurrency.values) c: 0.0};
    for (final h in _harvests) {
      final currency = AppCurrency.fromCode(h['currency'] as String?);
      totals[currency] =
          (totals[currency] ?? 0) +
          (h['kg_harvested'] as num).toDouble() *
              (h['price_per_kg'] as num).toDouble();
    }
    return totals;
  }

  Map<AppCurrency, double> get _totalOutstandingByCurrency {
    final value = _totalValueByCurrency;
    return {
      for (final c in AppCurrency.values)
        c: (value[c] ?? 0) - (_paidTotals[c] ?? 0),
    };
  }

  Future<void> _openAddHarvest() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddHarvestScreen()));
    if (result == true) _load();
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
                          value: '${_harvests.length}',
                          color: AppColors.brandGreenLight,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          icon: Icons.scale_outlined,
                          label: 'Total kg',
                          value: _totalKg.toStringAsFixed(1),
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
                                'Total value',
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
                      final pricePerKg = (h['price_per_kg'] as num).toDouble();
                      final total = kg * pricePerKg;
                      final currency = AppCurrency.fromCode(
                        h['currency'] as String?,
                      );
                      final customerName =
                          h['customers']?['name'] as String? ?? 'Unknown';
                      final date = DateTime.parse(h['harvest_date'] as String);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              const IconBadge(
                                icon: Icons.eco_outlined,
                                color: AppColors.brandGreenLight,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customerName,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${kg.toStringAsFixed(1)} kg @ ${formatMoney(pricePerKg, currency)}/kg',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _dateFormat.format(date),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatMoney(total, currency),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  color: AppColors.brandGreenDeep,
                                ),
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
