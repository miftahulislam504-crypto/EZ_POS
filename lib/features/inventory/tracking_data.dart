import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';

class StockUnit {
  const StockUnit({
    required this.id,
    required this.serial,
    required this.kind,
    required this.status,
    required this.productId,
    this.productName,
    required this.branchId,
    this.branchName,
    this.warrantyUntil,
    this.unitCost = 0,
  });

  final String id;
  final String serial;
  final String kind;
  final String status;
  final String productId;
  final String? productName;
  final String branchId;
  final String? branchName;
  final DateTime? warrantyUntil;
  final double unitCost;

  String get statusLabel => unitStatusLabels[status] ?? status;

  factory StockUnit.fromJson(Map<String, dynamic> j) => StockUnit(
        id: j['id'] as String,
        serial: j['serial_no'] as String,
        kind: j['kind'] as String,
        status: j['status'] as String,
        productId: j['product_id'] as String,
        productName: (j['products'] as Map?)?['name'] as String?,
        branchId: j['branch_id'] as String,
        branchName: (j['branches'] as Map?)?['name'] as String?,
        warrantyUntil: parseDate(j['warranty_until']),
        unitCost: dbl(j['unit_cost']),
      );
}

const unitStatusLabels = {
  'in_stock': 'In stock',
  'sold': 'Sold',
  'in_transit': 'In transit',
  'returned_to_supplier': 'Returned to supplier',
  'damaged': 'Damaged',
  'inspection': 'Needs inspection',
  'lost': 'Lost',
};

class BranchOption {
  const BranchOption({required this.id, required this.name, required this.kind, this.address, this.phone, this.isDefault = false, this.isActive = true});

  final String id;
  final String name;
  final String kind;
  final String? address;
  final String? phone;
  final bool isDefault;
  final bool isActive;

  bool get isWarehouse => kind == 'warehouse';

  factory BranchOption.fromJson(Map<String, dynamic> j) => BranchOption(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: (j['kind'] as String?) ?? 'branch',
        address: j['address'] as String?,
        phone: j['phone'] as String?,
        isDefault: j['is_default'] == true,
        isActive: j['is_active'] != false,
      );
}

class ExpiryRow {
  const ExpiryRow({
    required this.productId,
    required this.productName,
    required this.batchNo,
    required this.expiry,
    required this.quantity,
    required this.value,
    required this.daysLeft,
    required this.expired,
    this.branchName,
  });

  final String productId;
  final String productName;
  final String batchNo;
  final DateTime expiry;
  final double quantity;
  final double value;
  final int daysLeft;
  final bool expired;
  final String? branchName;

  factory ExpiryRow.fromJson(Map<String, dynamic> j) => ExpiryRow(
        productId: j['product_id'] as String,
        productName: (j['product_name'] as String?) ?? '',
        batchNo: (j['batch_no'] as String?) ?? '',
        expiry: parseDate(j['expiry_date']) ?? DateTime.now(),
        quantity: dbl(j['quantity_left']),
        value: dbl(j['value']),
        daysLeft: intOf(j['days_left']),
        expired: j['expired'] == true,
        branchName: j['branch_name'] as String?,
      );
}

class UnitEvent {
  const UnitEvent({required this.type, this.from, this.to, this.note, required this.at});

  final String type;
  final String? from;
  final String? to;
  final String? note;
  final DateTime at;
}

class SerialInfo {
  const SerialInfo(this.raw);

  final Map<String, dynamic> raw;

  String get serial => raw['serial_no'] as String;
  String get kind => raw['kind'] as String;
  String get status => raw['status'] as String;
  String get productName => (raw['product_name'] as String?) ?? '';
  String? get branchName => raw['branch_name'] as String?;
  double get unitCost => dbl(raw['unit_cost']);
  DateTime? get warrantyUntil => parseDate(raw['warranty_until']);
  DateTime? get soldAt => parseDate(raw['sold_at']);
  String? get invoiceNo => raw['invoice_no'] as String?;
  String? get customerName => raw['customer_name'] as String?;
  String? get customerPhone => raw['customer_phone'] as String?;
  String? get purchaseNo => raw['purchase_no'] as String?;
  List<UnitEvent> get events => [
        for (final e in asRows(raw['events']))
          UnitEvent(
            type: e['event_type'] as String,
            from: e['from_status'] as String?,
            to: e['to_status'] as String?,
            note: e['note'] as String?,
            at: parseDate(e['at']) ?? DateTime.now(),
          )
      ];
}

typedef UnitQuery = ({String? productId, String? branchId, String status, String search, int limit});

class TrackingRepository {
  TrackingRepository(this._client);

  final SupabaseClient _client;

  Future<List<StockUnit>> units(UnitQuery q) async {
    var query = _client.from('stock_units').select('*, products(name), branches(name)');
    if (q.productId != null) query = query.eq('product_id', q.productId!);
    if (q.branchId != null) query = query.eq('branch_id', q.branchId!);
    if (q.status != 'all') query = query.eq('status', q.status);
    final s = safeSearch(q.search).toUpperCase();
    if (s.isNotEmpty) query = query.ilike('serial_no', '%$s%');
    final rows = await query.order('serial_no').limit(q.limit);
    return [for (final r in rows) StockUnit.fromJson(r)];
  }

  Future<SerialInfo?> lookup(String serial) async {
    final res = await _client.rpc('serial_lookup', params: {'p_serial': serial});
    return res == null ? null : SerialInfo(asMap(res));
  }

  Future<List<ExpiryRow>> expiry(int days) async {
    final res = await _client.rpc('expiry_report', params: {'p_days': days, 'p_branch': null});
    return [for (final r in asRows(res)) ExpiryRow.fromJson(r)];
  }

  Future<List<BranchOption>> branches() async {
    final rows = await _client.from('branches').select().order('is_default', ascending: false).order('name');
    return [for (final r in rows) BranchOption.fromJson(r)];
  }

  Future<void> saveBranch(Map<String, dynamic> payload) => _client.rpc('save_branch', params: {'p': payload});
}

final trackingRepoProvider = Provider<TrackingRepository>((ref) => TrackingRepository(ref.watch(supabaseProvider)));

final stockUnitsProvider =
    FutureProvider.autoDispose.family<List<StockUnit>, UnitQuery>((ref, q) => ref.watch(trackingRepoProvider).units(q));

final serialLookupProvider =
    FutureProvider.autoDispose.family<SerialInfo?, String>((ref, serial) => ref.watch(trackingRepoProvider).lookup(serial));

final expiryProvider = FutureProvider.autoDispose.family<List<ExpiryRow>, int>((ref, days) => ref.watch(trackingRepoProvider).expiry(days));

final branchesProvider = FutureProvider.autoDispose<List<BranchOption>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(trackingRepoProvider).branches();
});

/// none, serial, imei, batch or expiry
final productTrackingProvider = FutureProvider.autoDispose.family<String, String>((ref, productId) async {
  final row = await ref.watch(supabaseProvider).from('products').select('tracking_type').eq('id', productId).single();
  return (row['tracking_type'] as String?) ?? 'none';
});

/// Serial/IMEI numbers sold on an invoice, grouped by invoice line id (for returns and exchanges).
final soldUnitsProvider = FutureProvider.autoDispose.family<Map<String, List<String>>, String>((ref, saleId) async {
  final rows = await ref.watch(supabaseProvider).from('stock_units').select('serial_no, sale_item_id').eq('sale_id', saleId).eq('status', 'sold');
  final out = <String, List<String>>{};
  for (final r in rows) {
    final k = r['sale_item_id'] as String?;
    if (k != null) out.putIfAbsent(k, () => []).add(r['serial_no'] as String);
  }
  return out;
});
