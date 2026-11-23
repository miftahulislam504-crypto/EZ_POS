import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.code,
    this.phone,
    this.altPhone,
    this.email,
    this.presentAddress,
    this.permanentAddress,
    this.nid,
    this.birthDate,
    this.occupation,
    this.workplace,
    this.emergencyName,
    this.emergencyPhone,
    this.remindersEnabled = true,
    this.group = 'regular',
    this.notes,
    this.isActive = true,
    this.balance = 0,
    this.lastEntry,
  });

  final String id;
  final String name;
  final String? code;
  final String? phone;
  final String? altPhone;
  final String? email;
  final String? presentAddress;
  final String? permanentAddress;
  final String? nid;
  final DateTime? birthDate;
  final String? occupation;
  final String? workplace;
  final String? emergencyName;
  final String? emergencyPhone;

  /// When off, no installment reminders are listed or sent for this customer.
  final bool remindersEnabled;
  final String group;
  final String? notes;
  final bool isActive;

  /// Positive = customer owes us (due). Negative = customer advance.
  final double balance;
  final DateTime? lastEntry;

  bool get hasDue => balance > 0.004;
  bool get hasAdvance => balance < -0.004;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String,
        code: j['code'] as String?,
        phone: j['phone'] as String?,
        altPhone: j['alt_phone'] as String?,
        email: j['email'] as String?,
        presentAddress: j['present_address'] as String?,
        permanentAddress: j['permanent_address'] as String?,
        nid: j['nid_number'] as String?,
        birthDate: parseDate(j['birth_date']),
        occupation: j['occupation'] as String?,
        workplace: j['workplace'] as String?,
        emergencyName: j['emergency_contact_name'] as String?,
        emergencyPhone: j['emergency_contact_phone'] as String?,
        remindersEnabled: j['reminders_enabled'] != false,
        group: (j['customer_group'] as String?) ?? 'regular',
        notes: j['notes'] as String?,
        isActive: j['is_active'] != false,
        balance: dbl(j['balance']),
        lastEntry: parseDate(j['last_entry']),
      );

  Map<String, dynamic> toCache() => {'id': id, 'name': name, 'phone': phone, 'balance': balance, 'group': group};

  factory Customer.fromCache(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        balance: dbl(j['balance']),
        group: (j['group'] as String?) ?? 'regular',
      );

  String get groupLabel => switch (group) {
        'wholesale' => 'Wholesale',
        'vip' => 'VIP',
        'corporate' => 'Corporate',
        'custom' => 'Custom',
        _ => 'Regular',
      };
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.date,
    required this.type,
    required this.description,
    required this.debit,
    required this.credit,
    this.refNo,
    this.refType,
    this.refId,
    this.balance = 0,
  });

  final String id;
  final DateTime date;
  final String type;
  final String description;
  final double debit;
  final double credit;
  final String? refNo;
  final String? refType;
  final String? refId;
  final double balance;

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String,
        date: parseDate(j['entry_date']) ?? DateTime.now(),
        type: j['entry_type'] as String,
        description: (j['description'] as String?) ?? '',
        debit: dbl(j['debit']),
        credit: dbl(j['credit']),
        refNo: j['reference_no'] as String?,
        refType: j['reference_type'] as String?,
        refId: j['reference_id'] as String?,
      );

  LedgerEntry withBalance(double b) => LedgerEntry(
        id: id,
        date: date,
        type: type,
        description: description,
        debit: debit,
        credit: credit,
        refNo: refNo,
        refType: refType,
        refId: refId,
        balance: b,
      );

  /// [receivable] true for customers (debit increases balance), false for suppliers (credit increases it).
  static List<LedgerEntry> withRunningBalance(List<LedgerEntry> asc, {required bool receivable}) {
    var running = 0.0;
    return [
      for (final e in asc)
        e.withBalance(running += receivable ? (e.debit - e.credit) : (e.credit - e.debit)),
    ];
  }
}

class OpenItem {
  const OpenItem({required this.id, required this.number, required this.date, required this.total, required this.due, required this.ageDays});

  final String id;
  final String number;
  final DateTime date;
  final double total;
  final double due;
  final int ageDays;
}

class PartySummary {
  const PartySummary({
    required this.totalPurchase,
    required this.totalPaid,
    required this.balance,
    this.totalReturns = 0,
    this.lastPurchase,
    this.lastPayment,
    this.openItems = const [],
  });

  final double totalPurchase;
  final double totalPaid;
  final double totalReturns;
  final double balance;
  final DateTime? lastPurchase;
  final DateTime? lastPayment;
  final List<OpenItem> openItems;

  factory PartySummary.fromCustomerJson(Map<String, dynamic> j) => PartySummary(
        totalPurchase: dbl(j['total_purchase']),
        totalPaid: dbl(j['total_paid']),
        totalReturns: dbl(j['total_returns']),
        balance: dbl(j['balance']),
        lastPurchase: parseDate(j['last_sale']),
        lastPayment: parseDate(j['last_payment']),
        openItems: [
          for (final r in asRows(j['open_invoices']))
            OpenItem(
              id: r['id'] as String,
              number: r['invoice_no'] as String,
              date: parseDate(r['sale_date']) ?? DateTime.now(),
              total: dbl(r['total']),
              due: dbl(r['due']),
              ageDays: intOf(r['age_days']),
            )
        ],
      );

  factory PartySummary.fromSupplierJson(Map<String, dynamic> j) => PartySummary(
        totalPurchase: dbl(j['total_purchase']),
        totalPaid: dbl(j['total_paid']),
        balance: dbl(j['balance']),
        lastPurchase: parseDate(j['last_purchase']),
        lastPayment: parseDate(j['last_payment']),
        openItems: [
          for (final r in asRows(j['open_purchases']))
            OpenItem(
              id: r['id'] as String,
              number: r['purchase_no'] as String,
              date: parseDate(r['purchase_date']) ?? DateTime.now(),
              total: dbl(r['total']),
              due: dbl(r['due']),
              ageDays: intOf(r['age_days']),
            )
        ],
      );
}

typedef PartyQuery = ({String search, String filter, int limit});

class CustomerRepository {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  Future<List<Customer>> list(PartyQuery q) async {
    var query = _client.from('customers_view').select();
    if (q.filter == 'due') query = query.gt('balance', 0);
    if (q.filter == 'advance') query = query.lt('balance', 0);
    if (q.filter == 'inactive') {
      query = query.eq('is_active', false);
    } else {
      query = query.eq('is_active', true);
    }
    final s = safeSearch(q.search);
    if (s.isNotEmpty) query = query.or('name.ilike.%$s%,phone.ilike.%$s%,code.ilike.%$s%,alt_phone.ilike.%$s%');
    final rows = await query.order('name').limit(q.limit);
    return [for (final r in rows) Customer.fromJson(r)];
  }

  Future<Customer?> byId(String id) async {
    final row = await _client.from('customers_view').select().eq('id', id).maybeSingle();
    return row == null ? null : Customer.fromJson(row);
  }

  Future<String> create(Map<String, dynamic> payload) async {
    final res = await _client.rpc('create_customer', params: {'p': payload});
    return res as String;
  }

  Future<void> update(String id, Map<String, dynamic> data) => _client.from('customers').update(data).eq('id', id);

  Future<List<LedgerEntry>> ledger(String id) async {
    final rows = await _client
        .from('customer_ledger')
        .select()
        .eq('customer_id', id)
        .order('entry_date')
        .order('created_at');
    return LedgerEntry.withRunningBalance([for (final r in rows) LedgerEntry.fromJson(r)], receivable: true);
  }

  Future<PartySummary> summary(String id) async {
    final res = await _client.rpc('customer_summary', params: {'p_customer': id});
    return PartySummary.fromCustomerJson(asMap(res));
  }

  Future<Map<String, dynamic>> receivePayment(Map<String, dynamic> payload) async {
    final res = await _client.rpc('record_customer_payment', params: {'p': payload});
    return asMap(res);
  }
}

final customerRepoProvider = Provider<CustomerRepository>((ref) => CustomerRepository(ref.watch(supabaseProvider)));

final customersProvider = FutureProvider.autoDispose.family<List<Customer>, PartyQuery>((ref, q) {
  return ref.watch(customerRepoProvider).list(q);
});

final customerProvider = FutureProvider.autoDispose.family<Customer?, String>((ref, id) {
  return ref.watch(customerRepoProvider).byId(id);
});

final customerLedgerProvider = FutureProvider.autoDispose.family<List<LedgerEntry>, String>((ref, id) {
  return ref.watch(customerRepoProvider).ledger(id);
});

final customerSummaryProvider = FutureProvider.autoDispose.family<PartySummary, String>((ref, id) {
  return ref.watch(customerRepoProvider).summary(id);
});
