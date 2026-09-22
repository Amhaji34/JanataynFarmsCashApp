import 'package:intl/intl.dart';
import '../main.dart';

final _dbDateFormat = DateFormat('yyyy-MM-dd');

/// Records a customer payment (upfront-at-harvest or a later standalone
/// payment) and feeds the same amount into the Revenue funding account as
/// a `fund_add` — this is the one place harvest sales connect to the
/// `accounts` ledger. From Revenue, funds reach Petty Cash the normal way
/// (Settings > Accounts > Transfer), same as any other funding source.
Future<void> recordCustomerPayment({
  required String customerId,
  String? harvestId,
  required double amount,
  required DateTime date,
  String note = '',
}) async {
  final dateStr = _dbDateFormat.format(date);
  final trimmedNote = note.trim();

  await supabase.from('customer_payments').insert({
    'customer_id': customerId,
    'harvest_id': harvestId,
    'amount': amount,
    'payment_date': dateStr,
    'note': trimmedNote.isEmpty ? null : trimmedNote,
  });

  final revenueAccount = await supabase
      .from('accounts')
      .select()
      .eq('name', 'Revenue')
      .single();

  await supabase.from('account_transactions').insert({
    'account_id': revenueAccount['id'],
    'type': 'fund_add',
    'amount': amount,
    'transaction_date': dateStr,
    'note': trimmedNote.isEmpty ? 'Harvest sale payment' : trimmedNote,
  });
}
