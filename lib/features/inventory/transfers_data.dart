import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';

const transferStatusLabels = {
  'requested': 'Requested',
  'in_transit': 'In transit',
  'partially_received': 'Partly received',
  'received': 'Received',
  'cancelled': 'Cancelled',
};

class TransferRow {
  const TransferRow({
    required this.id,
    required this.transferNo,
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
    required this.status,
    this.note,
    required this.requestedAt,
    this.dispatchedAt,
    this.receivedAt,
    this.cancelReason,
  });

  final String id;
  final String transferNo;
  final String fromId;
  final String fromName;
  final String toId;
  final String toName;
  final String status;
  final String? note;
  final DateTime requestedAt;
  final DateTime? dispatchedAt;
  final DateTime? receivedAt;
  final String? cancelReason;

  String get statusLabel => transferStatusLabels[status] ?? status;

  factory TransferRow.fromJson(Map<String, dynamic> j) => TransferRow(
        id: j['id'] as String,
        transferNo: j['transfer_no'] as String,
        fromId: j['from_branch_id'] as String,
        fromName: (j['from_branch'] as Map?)?['name'] as String? ?? '',
        toId: j['to_branch_id'] as String,
        toName: (j['to_branch'] as Map?)?['name'] as String? ?? '',
        status: j['status'] as String,
        note: j['note'] as String?,
        requestedAt: parseDate(j['requested_at']) ?? DateTime.now(),
        dispatchedAt: parseDate(j['dispatched_at']),
        receivedAt: parseDate(j['received_at']),
        cancelReason: j['cancel_reason'] as String?,
      );
}

class TransferItem {
  const TransferItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.sent,
    required this.received,
    this.serials = const [],
    this.receivedSerials = const [],
    this.shortageReason,
    this.trackingType = 'none',
  });

  final String id;
  final String productId;
  final String name;
  final double quantity;
  final double sent;
  final double received;
  final List<String> serials;
  final List<String> receivedSerials;
  final String? shortageReason;
  final String trackingType;

  double get onTheWay => (sent - received).clamp(0, double.infinity).toDouble();
  bool get usesSerials => trackingType == 'serial' || trackingType == 'imei';
  List<String> get pendingSerials => [for (final s in serials) if (!receivedSerials.contains(s)) s];

  factory TransferItem.fromJson(Map<String, dynamic> j) => TransferItem(
        id: j['id'] as String,
        productId: j['product_id'] as String,
        name: j['product_name'] as String,
        quantity: dbl(j['quantity']),
        sent: dbl(j['sent_quantity']),
        received: dbl(j['received_quantity']),
        serials: [for (final s in (j['serials'] as List? ?? const [])) s.toString()],
        receivedSerials: [for (final s in (j['received_serials'] as List? ?? const [])) s.toString()],
        shortageReason: j['shortage_reason'] as String?,
        trackingType: (j['products'] as Map?)?['tracking_type'] as String? ?? 'none',
      );
}

class TransferDetail {
  const TransferDetail(this.row, this.items);

  final TransferRow row;
  final List<TransferItem> items;
}

class StockCountRow {
  const StockCountRow({required this.id, required this.countNo, required this.status, this.note, required this.createdAt, this.items = const []});

  final String id;
  final String countNo;
  final String status;
  final String? note;
  final DateTime createdAt;
  final List<StockCountItem> items;

  bool get isDraft => status == 'draft';
}

class StockCountItem {
  const StockCountItem({required this.productId, required this.name, required this.system, required this.counted, this.reason});

  final String productId;
  final String name;
  final double system;
  final double counted;
  final String? reason;

  double get difference => counted - system;
}

typedef TransferQuery = ({String status, int limit});

class TransfersRepository {
  TransfersRepository(this._client);

  final SupabaseClient _client;

  static const _select = '*, from_branch:branches!stock_transfers_from_branch_id_fkey(name), to_branch:branches!stock_transfers_to_branch_id_fkey(name)';

  Future<List<TransferRow>> list(TransferQuery q) async {
    var query = _client.from('stock_transfers').select(_select);
    if (q.status != 'all') query = query.eq('status', q.status);
    final rows = await query.order('requested_at', ascending: false).limit(q.limit);
    return [for (final r in rows) TransferRow.fromJson(r)];
  }

  Future<TransferDetail> detail(String id) async {
    final row = await _client.from('stock_transfers').select(_select).eq('id', id).single();
    final items = await _client.from('stock_transfer_items').select('*, products(tracking_type)').eq('transfer_id', id).order('product_name');
    return TransferDetail(TransferRow.fromJson(row), [for (final r in items) TransferItem.fromJson(r)]);
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async =>
      asMap(await _client.rpc('create_stock_transfer', params: {'p': payload}));

  Future<void> dispatch(Map<String, dynamic> payload) => _client.rpc('dispatch_stock_transfer', params: {'p': payload});

  Future<void> receive(Map<String, dynamic> payload) => _client.rpc('receive_stock_transfer', params: {'p': payload});

  Future<void> cancel(String id, String reason) => _client.rpc('cancel_stock_transfer', params: {'p_id': id, 'p_reason': reason});

  Future<List<StockCountRow>> counts() async {
    final rows = await _client.from('stock_counts').select().order('created_at', ascending: false).limit(50);
    return [
      for (final r in rows)
        StockCountRow(
          id: r['id'] as String,
          countNo: r['count_no'] as String,
          status: r['status'] as String,
          note: r['note'] as String?,
          createdAt: parseDate(r['created_at']) ?? DateTime.now(),
        )
    ];
  }

  Future<StockCountRow> countDetail(String id) async {
    final r = await _client.from('stock_counts').select().eq('id', id).single();
    final items = await _client.from('stock_count_items').select().eq('count_id', id).order('product_name');
    return StockCountRow(
      id: r['id'] as String,
      countNo: r['count_no'] as String,
      status: r['status'] as String,
      note: r['note'] as String?,
      createdAt: parseDate(r['created_at']) ?? DateTime.now(),
      items: [
        for (final i in items)
          StockCountItem(
            productId: i['product_id'] as String,
            name: i['product_name'] as String,
            system: dbl(i['system_quantity']),
            counted: dbl(i['counted_quantity']),
            reason: i['reason'] as String?,
          )
      ],
    );
  }

  Future<Map<String, dynamic>> saveCount(Map<String, dynamic> payload) async =>
      asMap(await _client.rpc('save_stock_count', params: {'p': payload}));
}

final transfersRepoProvider = Provider<TransfersRepository>((ref) => TransfersRepository(ref.watch(supabaseProvider)));

final transfersProvider =
    FutureProvider.autoDispose.family<List<TransferRow>, TransferQuery>((ref, q) => ref.watch(transfersRepoProvider).list(q));

final transferDetailProvider =
    FutureProvider.autoDispose.family<TransferDetail, String>((ref, id) => ref.watch(transfersRepoProvider).detail(id));

final stockCountsProvider = FutureProvider.autoDispose<List<StockCountRow>>((ref) => ref.watch(transfersRepoProvider).counts());

final stockCountDetailProvider =
    FutureProvider.autoDispose.family<StockCountRow, String>((ref, id) => ref.watch(transfersRepoProvider).countDetail(id));
