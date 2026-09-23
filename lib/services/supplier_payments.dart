import 'package:intl/intl.dart';
import '../main.dart';
import '../utils/currency.dart';

final _dbDateFormat = DateFormat('yyyy-MM-dd');

/// Records a supplier payment (paid-now-at-purchase or a later standalone
/// payment) and, unlike a customer payment, also books it as a real
/// `expense` transaction under the "Supplier purchases" category — a
/// supplier payment is cash actually leaving Petty Cash, not money coming
/// into a funding account that still needs a manual transfer. This keeps
/// the existing Petty Cash balance formula (and Reports/Transaction Log)
/// correct with no other code changes.
Future<void> recordSupplierPayment({
  required String supplierId,
  String? purchaseId,
  required double amount,
  required DateTime date,
  required AppCurrency currency,
  String note = '',
}) async {
  final dateStr = _dbDateFormat.format(date);
  final trimmedNote = note.trim();

  await supabase.from('supplier_payments').insert({
    'supplier_id': supplierId,
    'purchase_id': purchaseId,
    'amount': amount,
    'payment_date': dateStr,
    'note': trimmedNote.isEmpty ? null : trimmedNote,
    'currency': currency.code,
  });

  final txn = await supabase
      .from('transactions')
      .insert({
        'type': 'expense',
        'amount': amount,
        'currency': currency.code,
        'transaction_date': dateStr,
        'note': trimmedNote.isEmpty ? 'Supplier payment' : trimmedNote,
      })
      .select()
      .single();

  await supabase.from('transaction_items').insert({
    'transaction_id': txn['id'],
    'category': 'Supplier purchases',
    'amount': amount,
    'note': trimmedNote.isEmpty ? null : trimmedNote,
  });
}
