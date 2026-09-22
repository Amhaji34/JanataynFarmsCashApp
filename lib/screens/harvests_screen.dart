import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import 'add_harvest_screen.dart';

/// Every harvest logged, newest first, with summary stats (how many
/// harvests, total kg, total value, how much of that has been collected).
/// Each harvest doubles as its sale record - see add_harvest_screen.dart.
class HarvestsScreen extends StatefulWidget {
  const HarvestsScreen({super.key});

  @override
  State<HarvestsScreen> createState() => _HarvestsScreenState();
}

class _HarvestsScreenState extends State<HarvestsScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _harvests = [];
  Map<String, double> _paidByCustomer = {};
  String? _role;

  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
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
          .select('customer_id, amount');
      final paidByCustomer = <String, double>{};
      for (final p in List<Map<String, dynamic>>.from(paymentsData)) {
        final id = p['customer_id'] as String;
        paidByCustomer[id] =
            (paidByCustomer[id] ?? 0) + (p['amount'] as num).toDouble();
      }

      setState(() {
        _harvests = List<Map<String, dynamic>>.from(harvestsData);
        _paidByCustomer = paidByCustomer;
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

  double get _totalValue => _harvests.fold(
    0,
    (sum, h) =>
        sum +
        (h['kg_harvested'] as num).toDouble() *
            (h['price_per_kg'] as num).toDouble(),
  );

  double get _totalPaid =>
      _paidByCustomer.values.fold(0, (sum, v) => sum + v);

  double get _totalOutstanding => _totalValue - _totalPaid;

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
                        child: StatTile(
                          icon: Icons.attach_money,
                          label: 'Total value',
                          value: _currency.format(_totalValue),
                          color: AppColors.cashIn,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          icon: Icons.pending_outlined,
                          label: 'Total outstanding',
                          value: _currency.format(_totalOutstanding),
                          color: AppColors.expense,
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
                      final customerName =
                          h['customers']?['name'] as String? ?? 'Unknown';
                      final date = DateTime.parse(
                        h['harvest_date'] as String,
                      );
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                      '${kg.toStringAsFixed(1)} kg @ ${_currency.format(pricePerKg)}/kg',
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
                                _currency.format(total),
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
