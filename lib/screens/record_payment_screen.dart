import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/customer_payments.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Records a payment from a customer against their outstanding balance.
/// The amount also feeds the Revenue funding account (see
/// services/customer_payments.dart).
class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.outstanding,
  });

  final String customerId;
  final String customerName;
  final double outstanding;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _dateFormat = DateFormat('MMM d, yyyy');
  final _currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
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

    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      setState(() => _errorMessage = 'Enter an amount greater than zero.');
      return;
    }
    if (amount > widget.outstanding + 0.01) {
      setState(
        () => _errorMessage =
            '${widget.customerName} only owes ${_currency.format(widget.outstanding)}.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await recordCustomerPayment(
        customerId: widget.customerId,
        amount: amount,
        date: _selectedDate,
        note: _noteController.text.trim(),
      );
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
      appBar: AppBar(title: const Text('Record payment')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.expense.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.expense.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: AppColors.expense,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.customerName} owes ${_currency.format(widget.outstanding)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.expense,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

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
          const SizedBox(height: 16),

          const SectionLabel('AMOUNT'),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: '\$0.00',
              prefixText: '\$ ',
              prefixStyle: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 16),

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
                  : const Text('Record payment'),
            ),
          ),
        ],
      ),
    );
  }
}
