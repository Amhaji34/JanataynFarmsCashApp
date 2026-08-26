import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _staff = [];

  final _nameController = TextEditingController();
  final _salaryController = TextEditingController();
  bool _adding = false;
  String? _addError;

  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);
    try {
      final data = await supabase.from('staff').select().order('name');
      setState(() {
        _staff = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load staff: $e';
        _loading = false;
      });
    }
  }

  Future<void> _addStaff() async {
    final name = _nameController.text.trim();
    final salary = double.tryParse(_salaryController.text) ?? 0;
    if (name.isEmpty) return;

    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      await supabase.from('staff').insert({
        'name': name,
        'base_salary': salary,
      });
      _nameController.clear();
      _salaryController.clear();
      await _loadStaff();
    } catch (e) {
      setState(() => _addError = 'Could not add staff: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('ADD A STAFF MEMBER'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Staff name',
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.person_add_alt_outlined,
                        size: 19,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _salaryController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          decoration: const InputDecoration(
                            hintText: 'Base salary',
                            isDense: true,
                            prefixText: '\$ ',
                          ),
                          onSubmitted: (_) => _addStaff(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _adding ? null : _addStaff,
                          child: _adding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Add'),
                        ),
                      ),
                    ],
                  ),
                  if (_addError != null) ...[
                    const SizedBox(height: 12),
                    ErrorNote(_addError!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (!_loading && _errorMessage == null && _staff.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: SectionLabel(
                  'TEAM',
                  trailing: Text(
                    '${_staff.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? Center(child: ErrorNote(_errorMessage!))
                  : _staff.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'No staff yet',
                      subtitle:
                          'Add your farm workers here so you can record '
                          'payroll and advances for them.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _staff.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final member = _staff[index];
                        final name = member['name'] as String;
                        return AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              InitialsAvatar(name: name),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Base salary',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _currency.format(
                                  (member['base_salary'] as num).toDouble(),
                                ),
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.payroll,
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
      ),
    );
  }
}
