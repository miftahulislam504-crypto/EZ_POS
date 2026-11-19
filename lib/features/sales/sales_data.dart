import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/date_range_bar.dart';

class SaleRow {
  const SaleRow({
    required this.id,
    required this.invoiceNo,
    required this.date,
    required this.total,
    required this.paid,
    required this.due,
    required this.returned,
    required this.status,
    required this.paymentStatus,
    this.customerId,
    this.customerName,
    this.customerPhone,
  });

  final String id;
  final String invoiceNo;
  final DateTime date;
  final double total;
  final double paid;
  final double due;
  final double returned;
  final String status;
  final String paymentStatus;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;

  bool get isVoid => status == 'void';

  factory SaleRow.fromJson(Map<String, dynamic> j) => SaleRow(
        id: j['id'] as String,
        invoiceNo: j['invoice_no'] as String,
        date: parseDate(j['sale_date']) ?? DateTime.now(),
        total: dbl(j['total']),
        paid: dbl(j['paid_amount']),
        due: dbl(j['due_amount']),
        returned: dbl(j['returned_amount']),
        status: j['status'] as String,
        paymentStatus: j['payment_status'] as String,
        customerId: j['customer_id'] as String?,
        customerName: (j['customers'] as Map?)?['name'] as String?,
        customerPhone: (j['customers'] as Map?)?['phone'] as String?,
      );
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.productId,
    required this.name,
    this.sku,
    this.unit,
    required this.qty,
    required this.price,
    required this.discount,
    required this.taxRate,
    required this.net,
    required this.tax,
    required this.total,
    required this.returnedQty,
  });

  final String id;
  final String productId;
  final String name;
  final String? sku;
  final String? unit;
  final double qty;
  final double price;
  final double discount;
  final double taxRate;
  final double net;
  final double tax;
  final double total;
  final double returnedQty;

  double get returnable => qty - returnedQty;

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        id: j['id'] as String,
        productId: j['product_id'] as String,
        name: j['product_name'] as String,
        sku: j['sku'] as String?,
        unit: j['unit_name'] as String?,
        qty: dbl(j['quantity']),
        price: dbl(j['unit_price']),
        discount: dbl(j['discount']),
        taxRate: dbl(j['tax_rate']),
        net: dbl(j['net_amount']),
        tax: dbl(j['tax_amount']),
        total: dbl(j['line_total']),
        returnedQty: dbl(j['returned_quantity']),
      );
}

class SalePayment {
  const SalePayment({required this.account, required this.amount, this.reference});

  final String account;
  final double amount;
  final String? reference;
}

class SaleReturnRef {
  const SaleReturnRef({required this.id, required this.returnNo, required this.date, required this.total, required this.refund});

  final String id;
  final String returnNo;
  final DateTime date;
  final double total;
  final double refund;
}

class SaleDetail {
  const SaleDetail({
    required this.row,
    required this.items,
    required this.payments,
    required this.returns,
    required this.subtotal,
    required this.itemDiscount,
    required this.invoiceDiscount,
    required this.tax,
    this.note,
    this.voidReason,
    this.cashierName,
    this.customerAddress,
  });

  final SaleRow row;
  final List<SaleItem> items;
  final List<SalePayment> payments;
  final List<SaleReturnRef> returns;
  final double subtotal;
  final double itemDiscount;
  final double invoiceDiscount;
  final double tax;
  final String? note;
  final String? voidReason;
  final String? cashierName;
  final String? customerAddress;
}

typedef SaleQuery = ({DateRange? range, String search, String? customerId, String status, int limit});

class SalesRepository {
  SalesRepository(this._client);

  final SupabaseClient _client;

  Future<List<SaleRow>> list(SaleQuery q) async {
    var query = _client.from('sales').select('*, customers(name, phone)');
    if (q.range != null) query = query.gte('sale_date', q.range!.fromTs).lt('sale_date', q.range!.toTsExclusive);
    if (q.customerId != null) query = query.eq('customer_id', q.customerId!);
    if (q.status == 'void') query = query.eq('status', 'void');
    if (q.status == 'due') query = query.eq('status', 'completed').gt('due_amount', 0);
    if (q.status == 'completed') query = query.eq('status', 'completed');
    final s = safeSearch(q.search);
    if (s.isNotEmpty) query = query.ilike('invoice_no', '%$s%');
    final rows = await query.order('sale_date', ascending: false).limit(q.limit);
    return [for (final r in rows) SaleRow.fromJson(r)];
  }

  Future<SaleDetail> detail(String id) async {
    final j = await _client
        .from('sales')
        .select('*, customers(name, phone, present_address), sale_items(*), sale_payments(*, payment_accounts(name)), sales_returns(id, return_no, return_date, total, refund_amount)')
        .eq('id', id)
        .single();
    String? cashier;
    final cashierId = j['cashier_id'] as String?;
    if (cashierId != null) {
      final m = await _client.from('business_members').select('full_name').eq('user_id', cashierId).maybeSingle();
      cashier = m?['full_name'] as String?;
    }
    final items = [for (final r in asRows(j['sale_items'])) SaleItem.fromJson(r)];
    final lineNos = {for (final r in asRows(j['sale_items'])) r['id'] as String: intOf(r['line_no'])};
    items.sort((a, b) => (lineNos[a.id] ?? 0).compareTo(lineNos[b.id] ?? 0));
    return SaleDetail(
      row: SaleRow.fromJson(j),
      items: items,
      payments: [
        for (final p in asRows(j['sale_payments']))
          SalePayment(
            account: (p['payment_accounts'] as Map?)?['name'] as String? ?? 'Payment',
            amount: dbl(p['amount']),
            reference: p['reference'] as String?,
          )
      ],
      returns: [
        for (final r in asRows(j['sales_returns']))
          SaleReturnRef(
            id: r['id'] as String,
            returnNo: r['return_no'] as String,
            date: parseDate(r['return_date']) ?? DateTime.now(),
            total: dbl(r['total']),
            refund: dbl(r['refund_amount']),
          )
      ],
      subtotal: dbl(j['subtotal']),
      itemDiscount: dbl(j['item_discount']),
      invoiceDiscount: dbl(j['invoice_discount']),
      tax: dbl(j['tax_amount']),
      note: j['note'] as String?,
      voidReason: j['void_reason'] as String?,
      cashierName: cashier,
      customerAddress: (j['customers'] as Map?)?['present_address'] as String?,
    );
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    final res = await _client.rpc('create_sale', params: {'p': payload});
    return asMap(res);
  }

  Future<void> voidSale(String id, String reason) => _client.rpc('void_sale', params: {'p_sale': id, 'p_reason': reason});

  Future<Map<String, dynamic>> createReturn(Map<String, dynamic> payload) async {
    final res = await _client.rpc('create_sales_return', params: {'p': payload});
    return asMap(res);
  }
}

final salesRepoProvider = Provider<SalesRepository>((ref) => SalesRepository(ref.watch(supabaseProvider)));

final salesListProvider = FutureProvider.autoDispose.family<List<SaleRow>, SaleQuery>((ref, q) {
  return ref.watch(salesRepoProvider).list(q);
});

final saleDetailProvider = FutureProvider.autoDispose.family<SaleDetail, String>((ref, id) {
  return ref.watch(salesRepoProvider).detail(id);
});

// ---------------------------------------------------------------- sales returns list
class ReturnRow {
  const ReturnRow({required this.id, required this.returnNo, required this.date, required this.total, required this.refund, required this.invoiceNo, required this.saleId, this.customerName, this.reason});

  final String id;
  final String returnNo;
  final DateTime date;
  final double total;
  final double refund;
  final String invoiceNo;
  final String saleId;
  final String? customerName;
  final String? reason;
}

typedef ReturnQuery = ({DateRange? range, int limit});

final salesReturnsProvider = FutureProvider.autoDispose.family<List<ReturnRow>, ReturnQuery>((ref, q) async {
  var query = ref.watch(supabaseProvider).from('sales_returns').select('*, customers(name), sales(invoice_no)');
  if (q.range != null) query = query.gte('return_date', q.range!.fromTs).lt('return_date', q.range!.toTsExclusive);
  final rows = await query.order('return_date', ascending: false).limit(q.limit);
  return [
    for (final r in rows)
      ReturnRow(
        id: r['id'] as String,
        returnNo: r['return_no'] as String,
        date: parseDate(r['return_date']) ?? DateTime.now(),
        total: dbl(r['total']),
        refund: dbl(r['refund_amount']),
        invoiceNo: (r['sales'] as Map?)?['invoice_no'] as String? ?? '',
        saleId: r['sale_id'] as String,
        customerName: (r['customers'] as Map?)?['name'] as String?,
        reason: r['reason'] as String?,
      )
  ];
});
