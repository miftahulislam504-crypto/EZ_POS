import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/date_range_bar.dart';

class PaymentRow {
  const PaymentRow({
    required this.id,
    required this.number,
    required this.date,
    required this.amount,
    required this.partyId,
    required this.partyName,
    required this.accountName,
    this.reference,
    this.note,
  });

  final String id;
  final String number;
  final DateTime date;
  final double amount;
  final String partyId;
  final String partyName;
  final String accountName;
  final String? reference;
  final String? note;
}

typedef PaymentQuery = ({DateRange? range, int limit});

final customerPaymentsProvider = FutureProvider.autoDispose.family<List<PaymentRow>, PaymentQuery>((ref, q) async {
  var query = ref.watch(supabaseProvider).from('customer_payments').select('*, customers(name), payment_accounts(name)');
  if (q.range != null) query = query.gte('payment_date', q.range!.fromTs).lt('payment_date', q.range!.toTsExclusive);
  final rows = await query.order('payment_date', ascending: false).limit(q.limit);
  return [
    for (final r in rows)
      PaymentRow(
        id: r['id'] as String,
        number: r['receipt_no'] as String,
        date: parseDate(r['payment_date']) ?? DateTime.now(),
        amount: dbl(r['amount']),
        partyId: r['customer_id'] as String,
        partyName: (r['customers'] as Map?)?['name'] as String? ?? 'Customer',
        accountName: (r['payment_accounts'] as Map?)?['name'] as String? ?? '',
        reference: r['reference'] as String?,
        note: r['note'] as String?,
      )
  ];
});

final supplierPaymentsProvider = FutureProvider.autoDispose.family<List<PaymentRow>, PaymentQuery>((ref, q) async {
  var query = ref.watch(supabaseProvider).from('supplier_payments').select('*, suppliers(name), payment_accounts(name)');
  if (q.range != null) query = query.gte('payment_date', q.range!.fromTs).lt('payment_date', q.range!.toTsExclusive);
  final rows = await query.order('payment_date', ascending: false).limit(q.limit);
  return [
    for (final r in rows)
      PaymentRow(
        id: r['id'] as String,
        number: r['payment_no'] as String,
        date: parseDate(r['payment_date']) ?? DateTime.now(),
        amount: dbl(r['amount']),
        partyId: r['supplier_id'] as String,
        partyName: (r['suppliers'] as Map?)?['name'] as String? ?? 'Supplier',
        accountName: (r['payment_accounts'] as Map?)?['name'] as String? ?? '',
        reference: r['reference'] as String?,
        note: r['note'] as String?,
      )
  ];
});
