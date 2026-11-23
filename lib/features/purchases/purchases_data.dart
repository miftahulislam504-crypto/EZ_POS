import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/date_range_bar.dart';

class PurchaseRow {
  const PurchaseRow({
    required this.id,
    required this.purchaseNo,
    required this.date,
    required this.total,
    required this.paid,
    required this.due,
    required this.status,
    this.supplierId,
    this.supplierName,
    this.supplierInvoiceNo,
  });

  final String id;
  final String purchaseNo;
  final DateTime date;
  final double total;
  final double paid;
  final double due;
  final String status;
  final String? supplierId;
  final String? supplierName;
  final String? supplierInvoiceNo;

  factory PurchaseRow.fromJson(Map<String, dynamic> j) => PurchaseRow(
        id: j['id'] as String,
        purchaseNo: j['purchase_no'] as String,
        date: parseDate(j['purchase_date']) ?? DateTime.now(),
        total: dbl(j['total']),
        paid: dbl(j['paid_amount']),
        due: dbl(j['due_amount']),
        status: j['status'] as String,
        supplierId: j['supplier_id'] as String?,
        supplierName: (j['suppliers'] as Map?)?['name'] as String?,
        supplierInvoiceNo: j['supplier_invoice_no'] as String?,
      );
}

class PurchaseItemRow {
  const PurchaseItemRow({required this.name, required this.qty, required this.unitCost, required this.discount, required this.total, required this.landed});

  final String name;
  final double qty;
  final double unitCost;
  final double discount;
  final double total;
  final double landed;
}

class PurchaseDetail {
  const PurchaseDetail({
    required this.row,
    required this.items,
    required this.payments,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.otherCharges,
    this.note,
    this.supplierPhone,
    this.supplierAddress,
  });

  final PurchaseRow row;
  final List<PurchaseItemRow> items;
  final List<({String account, double amount})> payments;
  final double subtotal;
  final double discount;
  final double tax;
  final double otherCharges;
  final String? note;
  final String? supplierPhone;
  final String? supplierAddress;
}

typedef PurchaseQuery = ({DateRange? range, String search, String? supplierId, String status, int limit});

class PurchaseRepository {
  PurchaseRepository(this._client);

  final SupabaseClient _client;

  Future<List<PurchaseRow>> list(PurchaseQuery q) async {
    var query = _client.from('purchases').select('*, suppliers(name)');
    if (q.range != null) query = query.gte('purchase_date', q.range!.fromIso).lte('purchase_date', q.range!.toIso);
    if (q.supplierId != null) query = query.eq('supplier_id', q.supplierId!);
    if (q.status == 'due') query = query.gt('due_amount', 0);
    final s = safeSearch(q.search);
    if (s.isNotEmpty) query = query.or('purchase_no.ilike.%$s%,supplier_invoice_no.ilike.%$s%');
    final rows = await query.order('purchase_date', ascending: false).order('created_at', ascending: false).limit(q.limit);
    return [for (final r in rows) PurchaseRow.fromJson(r)];
  }

  Future<Map<String, dynamic>> createReturn(Map<String, dynamic> payload) async =>
      asMap(await _client.rpc('create_purchase_return', params: {'p': payload}));

  Future<List<Map<String, dynamic>>> returnsFor(String purchaseId) async {
    final rows = await _client
        .from('purchase_returns')
        .select('id, return_no, return_date, total, refund_mode, refund_amount, reason')
        .eq('purchase_id', purchaseId)
        .order('return_date', ascending: false);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<PurchaseDetail> detail(String id) async {
    final j = await _client
        .from('purchases')
        .select('*, suppliers(name, phone, address), purchase_items(*), purchase_payments(*, payment_accounts(name))')
        .eq('id', id)
        .single();
    final items = asRows(j['purchase_items']);
    items.sort((a, b) => intOf(a['line_no']).compareTo(intOf(b['line_no'])));
    return PurchaseDetail(
      row: PurchaseRow.fromJson(j),
      items: [
        for (final i in items)
          PurchaseItemRow(
            name: i['product_name'] as String,
            qty: dbl(i['quantity']),
            unitCost: dbl(i['unit_cost']),
            discount: dbl(i['discount']),
            total: dbl(i['line_total']),
            landed: dbl(i['landed_unit_cost']),
          )
      ],
      payments: [
        for (final p in asRows(j['purchase_payments']))
          (account: (p['payment_accounts'] as Map?)?['name'] as String? ?? 'Payment', amount: dbl(p['amount']))
      ],
      subtotal: dbl(j['subtotal']),
      discount: dbl(j['discount']),
      tax: dbl(j['tax_amount']),
      otherCharges: dbl(j['other_charges']),
      note: j['note'] as String?,
      supplierPhone: (j['suppliers'] as Map?)?['phone'] as String?,
      supplierAddress: (j['suppliers'] as Map?)?['address'] as String?,
    );
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    final res = await _client.rpc('create_purchase', params: {'p': payload});
    return asMap(res);
  }
}

final purchaseRepoProvider = Provider<PurchaseRepository>((ref) => PurchaseRepository(ref.watch(supabaseProvider)));

final purchasesListProvider = FutureProvider.autoDispose.family<List<PurchaseRow>, PurchaseQuery>((ref, q) {
  return ref.watch(purchaseRepoProvider).list(q);
});

final purchaseDetailProvider = FutureProvider.autoDispose.family<PurchaseDetail, String>((ref, id) {
  return ref.watch(purchaseRepoProvider).detail(id);
});

final purchaseReturnsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
    (ref, id) => ref.watch(purchaseRepoProvider).returnsFor(id));
