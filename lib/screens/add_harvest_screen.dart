import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Logs a harvest as pure inventory intake: how much was picked and when.
/// It's deliberately not tied to a customer or a price - the produce may
/// sit unsold for a few days, and can end up sold to more than one
/// customer over time. Selling from this stock happens separately, via
/// add_sale_screen.dart (reached from harvest_detail_screen.dart).
class AddHarvestScreen extends StatefulWidget {
  const AddHarvestScreen({super.key});

  @override
  State<AddHarvestScreen> createState() => _AddHarvestScreenState();
}

class _AddHarvestScreenState extends State<AddHarvestScreen> {
  final _kgController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _dbDateFormat = DateFormat('yyyy-MM-dd');

  bool _saving = false;
  String? _errorMessage;

  double get _kg => double.tryParse(_kgController.text) ?? 0;

  @override
  void dispose() {
    _kgController.dispose();
    _noteController.dispose();
    super.dispose();
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

  Future<void> _save() async {
    setState(() => _errorMessage = null);

    if (_kg <= 0) {
      setState(() => _errorMessage = 'Enter how many kg were harvested.');
      return;
    }

    setState(() => _saving = true);
    try {
      await supabase.from('harvests').insert({
        'harvest_date': _dbDateFormat.format(_selectedDate),
        'kg_harvested': _kg,
        'note': _noteController.text.trim(),
      });

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _errorMessage = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add harvest')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionLabel('DATE'),
          const SizedBox(height: 8),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(AppStyles.radiusField),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppStyles.radiusField),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 17,
                      color: AppColors.brandGreen,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _dateFormat.format(_selectedDate),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Icon(
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

          const SectionLabel('KG HARVESTED'),
          const SizedBox(height: 8),
          TextField(
            controller: _kgController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: '0', suffixText: 'kg'),
          ),
          const SizedBox(height: 20),

          const SectionLabel('NOTE (OPTIONAL)'),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(hintText: 'Add a note'),
          ),
          const SizedBox(height: 24),

          if (_errorMessage != null) ...[
            ErrorNote(_errorMessage!),
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            height: 54,
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
                  : const Text('Save harvest'),
            ),
          ),
        ],
      ),
    );
  }
}
