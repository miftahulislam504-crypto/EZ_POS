import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';

class StockRow {
  const StockRow({
    required this.productId,
    required this.name,
    this.sku,
    this.barcode,
    this.imageUrl,
    this.category,
    this.unit,
    this.quantity = 0,
    this.damaged = 0,
    this.inspection = 0,
    this.avgCost = 0,
    this.value = 0,
    this.lowLimit = 0,
    this.status = 'ok',
  });

  final String productId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? imageUrl;
  final String? category;
  final String? unit;
  final double quantity;
  final double damaged;
  final double inspection;
  final double avgCost;
  final double value;
  final double lowLimit;
  final String status; // ok | low | out

  factory StockRow.fromJson(Map<String, dynamic> j) => StockRow(
        productId: j['product_id'] as String,
        name: j['name'] as String,
        sku: j['sku'] as String?,
        barcode: j['barcode'] as String?,
        imageUrl: j['image_url'] as String?,
        category: j['category'] as String?,
        unit: j['unit'] as String?,
        quantity: dbl(j['quantity']),
        damaged: dbl(j['damaged']),
        inspection: dbl(j['inspection']),
        avgCost: dbl(j['avg_cost']),
        value: dbl(j['value']),
        lowLimit: dbl(j['low_limit']),
        status: (j['status'] as String?) ?? 'ok',
      );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productName,
    required this.type,
    required this.bucket,
    required this.quantity,
    required this.createdAt,
    this.note,
    this.unit,
  });

  final String id;
  final String productName;
  final String type;
  final String bucket;
  final double quantity;
  final DateTime createdAt;
  final String? note;
  final String? unit;

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        id: j['id'] as String,
        productName: (j['products'] as Map?)?['name'] as String? ?? 'Product',
        unit: ((j['products'] as Map?)?['units'] as Map?)?['short_name'] as String?,
        type: j['movement_type'] as String,
        bucket: j['bucket'] as String,
        quantity: dbl(j['quantity']),
        createdAt: parseDate(j['created_at']) ?? DateTime.now(),
        note: j['note'] as String?,
      );

  String get typeLabel => switch (type) {
        'sale' => 'Sale',
        'sale_void' => 'Sale voided',
        'sales_return' => 'Sales return',
        'purchase' => 'Purchase',
        'adjust_opening' => 'Opening stock',
        'adjust_increase' => 'Stock added',
        'adjust_decrease' => 'Stock removed',
        'adjust_damage' => 'Damaged',
        'adjust_loss' => 'Loss',
        'adjust_expired' => 'Expired',
        _ => type,
      };
}

typedef StockQuery = ({String filter, String search, int limit});
typedef MovementQuery = ({String? productId, int limit});

class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<StockRow>> stockReport(StockQuery q) async {
    final res = await _client.rpc('stock_report', params: {
      'p_filter': q.filter,
      'p_search': q.search.isEmpty ? null : q.search,
      'p_limit': q.limit,
      'p_offset': 0,
    });
    return [for (final r in asRows(res)) StockRow.fromJson(r)];
  }

  Future<List<StockMovement>> movements(MovementQuery q) async {
    var query = _client.from('stock_movements').select('*, products(name, units(short_name))');
    if (q.productId != null) query = query.eq('product_id', q.productId!);
    final rows = await query.order('created_at', ascending: false).limit(q.limit);
    return [for (final r in rows) StockMovement.fromJson(r)];
  }

  Future<void> adjust({
    required String productId,
    required String kind,
    required double quantity,
    String? note,
    List<String>? serials,
    String? batchNo,
    DateTime? expiry,
  }) async {
    await _client.rpc('adjust_stock', params: {
      'p_product': productId,
      'p_branch': null,
      'p_qty': quantity,
      'p_kind': kind,
      'p_note': note,
      'p_serials': serials,
      'p_batch_no': batchNo,
      'p_expiry': expiry == null ? null : Fmt.iso(expiry),
    });
  }
}

final inventoryRepoProvider = Provider<InventoryRepository>((ref) => InventoryRepository(ref.watch(supabaseProvider)));

final stockReportProvider = FutureProvider.autoDispose.family<List<StockRow>, StockQuery>((ref, q) {
  return ref.watch(inventoryRepoProvider).stockReport(q);
});

final stockMovementsProvider = FutureProvider.autoDispose.family<List<StockMovement>, MovementQuery>((ref, q) {
  return ref.watch(inventoryRepoProvider).movements(q);
});
