import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../customers/customers_data.dart';

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.code,
    this.contactPerson,
    this.phone,
    this.altPhone,
    this.email,
    this.address,
    this.businessType,
    this.notes,
    this.isActive = true,
    this.balance = 0,
  });

  final String id;
  final String name;
  final String? code;
  final String? contactPerson;
  final String? phone;
  final String? altPhone;
  final String? email;
  final String? address;
  final String? businessType;
  final String? notes;
  final bool isActive;

  /// Positive = we owe the supplier (payable). Negative = advance paid to the supplier.
  final double balance;

  bool get hasPayable => balance > 0.004;
  bool get hasAdvance => balance < -0.004;

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String?,
        contactPerson: j['contact_person'] as String?,
        phone: j['phone'] as String?,
        altPhone: j['alt_phone'] as String?,
        email: j['email'] as String?,
        address: j['address'] as String?,
        businessType: j['business_type'] as String?,
        notes: j['notes'] as String?,
        isActive: j['is_active'] != false,
        balance: dbl(j['balance']),
      );
}

class SupplierRepository {
  SupplierRepository(this._client);

  final SupabaseClient _client;

  Future<List<Supplier>> list(PartyQuery q) async {
    var query = _client.from('suppliers_view').select();
    if (q.filter == 'due') query = query.gt('balance', 0);
    if (q.filter == 'advance') query = query.lt('balance', 0);
    query = query.eq('is_active', q.filter != 'inactive');
    final s = safeSearch(q.search);
    if (s.isNotEmpty) query = query.or('name.ilike.%$s%,phone.ilike.%$s%,code.ilike.%$s%,contact_person.ilike.%$s%');
    final rows = await query.order('name').limit(q.limit);
    return [for (final r in rows) Supplier.fromJson(r)];
  }

  Future<Supplier?> byId(String id) async {
    final row = await _client.from('suppliers_view').select().eq('id', id).maybeSingle();
    return row == null ? null : Supplier.fromJson(row);
  }

  Future<String> create(Map<String, dynamic> payload) async {
    final res = await _client.rpc('create_supplier', params: {'p': payload});
    return res as String;
  }

  Future<void> update(String id, Map<String, dynamic> data) => _client.from('suppliers').update(data).eq('id', id);

  Future<List<LedgerEntry>> ledger(String id) async {
    final rows = await _client.from('supplier_ledger').select().eq('supplier_id', id).order('entry_date').order('created_at');
    return LedgerEntry.withRunningBalance([for (final r in rows) LedgerEntry.fromJson(r)], receivable: false);
  }

  Future<PartySummary> summary(String id) async {
    final res = await _client.rpc('supplier_summary', params: {'p_supplier': id});
    return PartySummary.fromSupplierJson(asMap(res));
  }

  Future<Map<String, dynamic>> makePayment(Map<String, dynamic> payload) async {
    final res = await _client.rpc('record_supplier_payment', params: {'p': payload});
    return asMap(res);
  }
}

final supplierRepoProvider = Provider<SupplierRepository>((ref) => SupplierRepository(ref.watch(supabaseProvider)));

final suppliersProvider = FutureProvider.autoDispose.family<List<Supplier>, PartyQuery>((ref, q) {
  return ref.watch(supplierRepoProvider).list(q);
});

final supplierProvider = FutureProvider.autoDispose.family<Supplier?, String>((ref, id) {
  return ref.watch(supplierRepoProvider).byId(id);
});

final supplierLedgerProvider = FutureProvider.autoDispose.family<List<LedgerEntry>, String>((ref, id) {
  return ref.watch(supplierRepoProvider).ledger(id);
});

final supplierSummaryProvider = FutureProvider.autoDispose.family<PartySummary, String>((ref, id) {
  return ref.watch(supplierRepoProvider).summary(id);
});
