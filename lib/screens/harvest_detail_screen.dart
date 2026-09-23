import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../widgets/app_ui.dart';
import 'add_sale_screen.dart';

/// One harvest's kg harvested/sold/remaining plus every sale recorded
/// against it - a harvest can be sold to more than one customer, on more
/// than one date, at different prices - this is where that shows up.
class HarvestDetailScreen extends StatefulWidget {
  const HarvestDetailScreen({
    super.key,
    required this.harvestId,
    required this.harvestNumber,
    required this.harvestDate,
    required this.kgHarvested,
    this.note,
  });

  final String harvestId;
  final int harvestNumber;
  final DateTime harvestDate;
  final double kgHarvested;
  final String? note;

  @override
  State<HarvestDetailScreen> createState() => _HarvestDetailScreenState();
}

class _HarvestDetailScreenState extends State<HarvestDetailScreen> {
  bool _loading = true;
  String? _errorMessage;
  String? _role;
  List<Map<String, dynamic>> _sales = [];

  final _dateFormat = DateFormat('MMM d, yyyy');

  double get _kgSold =>
      _sales.fold(0, (sum, s) => sum + (s['kg_sold'] as num).toDouble());
  double get _kgRemaining =>
      (widget.kgHarvested - _kgSold).clamp(0, double.infinity);

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
      final data = await supabase
          .from('harvest_sales')
          .select('*, customers(name)')
          .eq('harvest_id', widget.harvestId)
          .order('sale_date', ascending: false);
      setState(() {
        _sales = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load sales: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openAddSale() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddSaleScreen(preselectedHarvestId: widget.harvestId),
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final fullySold = _kgRemaining <= 0.01;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '#H${widget.harvestNumber} · ${_dateFormat.format(widget.harvestDate)}',
        ),
      ),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  AppCard(
                    accent: fullySold
                        ? AppColors.neutral
                        : AppColors.brandGreenLight,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(
                              icon: Icons.eco_outlined,
                              color: fullySold
                                  ? AppColors.neutral
                                  : AppColors.brandGreenLight,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                fullySold ? 'Fully sold' : 'In stock',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _kgStat(
                                'Harvested',
                                widget.kgHarvested,
                                AppColors.brandGreen,
                              ),
                            ),
                            Expanded(
                              child: _kgStat(
                                'Sold',
                                _kgSold,
                                AppColors.brandNavy,
                              ),
                            ),
                            Expanded(
                              child: _kgStat(
                                'Remaining',
                                _kgRemaining,
                                fullySold
                                    ? AppColors.neutral
                                    : AppColors.cashIn,
                              ),
                            ),
                          ],
                        ),
                        if (widget.note != null && widget.note!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.note!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_role == 'admin') ...[
                    const SizedBox(height: 14),
                    if (fullySold)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.neutral.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                            AppStyles.radiusField,
                          ),
                        ),
                        child: const Text(
                          'Fully sold — nothing left to sell',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _openAddSale,
                          icon: const Icon(Icons.sell_outlined, size: 18),
                          label: const Text('Add sale'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),
                  const SectionLabel('SALES'),
                  const SizedBox(height: 10),
                  if (_sales.isEmpty)
                    const EmptyState(
                      icon: Icons.sell_outlined,
                      title: 'Not sold yet',
                      subtitle:
                          'Sales recorded against this harvest will '
                          'show up here.',
                    )
                  else
                    ..._sales.map((s) {
                      final kg = (s['kg_sold'] as num).toDouble();
                      final pricePerKg = (s['price_per_kg'] as num).toDouble();
                      final transportFee = (s['transport_fee'] as num? ?? 0)
                          .toDouble();
                      final owed = (kg * pricePerKg - transportFee).clamp(
                        0.0,
                        double.infinity,
                      );
                      final currency = AppCurrency.fromCode(
                        s['currency'] as String?,
                      );
                      final customerName =
                          s['customers']?['name'] as String? ?? 'Unknown';
                      final date = DateTime.parse(s['sale_date'] as String);
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
                                icon: Icons.sell_outlined,
                                color: AppColors.brandNavy,
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
                                      transportFee > 0
                                          ? '${kg.toStringAsFixed(1)} kg @ ${formatMoney(pricePerKg, currency)}/kg '
                                                '(−${formatMoney(transportFee, currency)} transport)'
                                          : '${kg.toStringAsFixed(1)} kg @ ${formatMoney(pricePerKg, currency)}/kg',
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
                                formatMoney(owed, currency),
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

  Widget _kgStat(String label, double kg, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
        ),
        const SizedBox(height: 3),
        Text(
          '${kg.toStringAsFixed(1)} kg',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
