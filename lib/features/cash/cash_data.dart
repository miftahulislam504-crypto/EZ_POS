import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';

const sourceLabels = {
  'sale_payment': 'Sales received',
  'customer_payment': 'Customer dues collected',
  'installment_payment': 'Installments collected',
  'sale_void': 'Voided sales refunded',
  'sales_return_refund': 'Sales refunds',
  'purchase_payment': 'Paid at purchase',
  'supplier_payment': 'Supplier payments',
  'purchase_return_refund': 'Supplier refunds received',
  'expense': 'Expenses',
  'expense_void': 'Expenses reversed',
  'account_deposit': 'Cash added',
  'account_withdrawal': 'Cash taken out',
  'account_transfer': 'Transfers',
  'cash_difference': 'Cash difference',
};

class RegisterRow {
  const RegisterRow({required this.id, required this.branchId, required this.name, required this.isActive});

  final String id;
  final String branchId;
  final String name;
  final bool isActive;
}

class ShiftRow {
  const ShiftRow({
    required this.id,
    required this.shiftNo,
    required this.registerName,
    required this.openedByName,
    required this.openedAt,
    required this.openingCash,
    required this.status,
    this.closedAt,
    this.expected,
    this.counted,
    this.difference,
    this.reason,
  });

  final String id;
  final String shiftNo;
  final String registerName;
  final String? openedByName;
  final DateTime openedAt;
  final double openingCash;
  final String status;
  final DateTime? closedAt;
  final double? expected;
  final double? counted;
  final double? difference;
  final String? reason;

  bool get isOpen => status == 'open';

  factory ShiftRow.fromJson(Map<String, dynamic> j) => ShiftRow(
        id: j['id'] as String,
        shiftNo: j['shift_no'] as String,
        registerName: (j['cash_registers'] as Map?)?['name'] as String? ?? 'Counter',
        openedByName: j['opened_by_name'] as String?,
        openedAt: parseDate(j['opened_at']) ?? DateTime.now(),
        openingCash: dbl(j['opening_cash']),
        status: j['status'] as String,
        closedAt: parseDate(j['closed_at']),
        expected: j['expected_cash'] == null ? null : dbl(j['expected_cash']),
        counted: j['counted_cash'] == null ? null : dbl(j['counted_cash']),
        difference: j['difference'] == null ? null : dbl(j['difference']),
        reason: j['difference_reason'] as String?,
      );
}

class CashSummary {
  const CashSummary(this.raw);

  final Map<String, dynamic> raw;

  double get opening => dbl(raw['opening_cash']);
  double get expected => dbl(raw['expected_cash']);
  double get cashIn => dbl(raw['cash_in']);
  double get cashOut => dbl(raw['cash_out']);
  int get salesCount => intOf(asMap(raw['sales'])['count']);
  double get salesTotal => dbl(asMap(raw['sales'])['total']);
  List<({String source, String direction, double amount})> get bySource => [
        for (final r in asRows(raw['by_source'])) (source: r['source_type'] as String, direction: r['direction'] as String, amount: dbl(r['amount']))
      ];
  List<({String account, double inAmt, double outAmt})> get nonCash =>
      [for (final r in asRows(raw['non_cash'])) (account: r['account'] as String, inAmt: dbl(r['in']), outAmt: dbl(r['out']))];
}

class AccountBalance {
  const AccountBalance({required this.id, required this.name, required this.type, this.accountNo, required this.balance});

  final String id;
  final String name;
  final String type;
  final String? accountNo;
  final double balance;

  bool get isCash => type == 'cash';
}

class StatementRow {
  const StatementRow({required this.date, required this.direction, required this.amount, required this.source, required this.description, required this.balance});

  final DateTime date;
  final String direction;
  final double amount;
  final String source;
  final String description;
  final double balance;
}

class Statement {
  const Statement({required this.name, required this.opening, required this.closing, required this.totalIn, required this.totalOut, required this.rows});

  final String name;
  final double opening;
  final double closing;
  final double totalIn;
  final double totalOut;
  final List<StatementRow> rows;
}

class DayClosingRow {
  const DayClosingRow({
    required this.id,
    required this.date,
    required this.status,
    required this.opening,
    required this.expected,
    required this.counted,
    required this.difference,
    this.reason,
    this.closedByName,
    required this.closedAt,
    required this.summary,
    this.reopenReason,
  });

  final String id;
  final DateTime date;
  final String status;
  final double opening;
  final double expected;
  final double counted;
  final double difference;
  final String? reason;
  final String? closedByName;
  final DateTime closedAt;
  final Map<String, dynamic> summary;
  final String? reopenReason;

  bool get isClosed => status == 'closed';

  factory DayClosingRow.fromJson(Map<String, dynamic> j) => DayClosingRow(
        id: j['id'] as String,
        date: parseDate(j['closing_date']) ?? DateTime.now(),
        status: j['status'] as String,
        opening: dbl(j['opening_cash']),
        expected: dbl(j['expected_cash']),
        counted: dbl(j['counted_cash']),
        difference: dbl(j['difference']),
        reason: j['difference_reason'] as String?,
        closedByName: j['closed_by_name'] as String?,
        closedAt: parseDate(j['closed_at']) ?? DateTime.now(),
        summary: asMap(j['summary']),
        reopenReason: j['reopen_reason'] as String?,
      );
}

class CashRepository {
  CashRepository(this._client);

  final SupabaseClient _client;

  Future<List<RegisterRow>> registers() async {
    final rows = await _client.from('cash_registers').select().order('name');
    return [
      for (final r in rows)
        RegisterRow(id: r['id'] as String, branchId: r['branch_id'] as String, name: r['name'] as String, isActive: r['is_active'] != false)
    ];
  }

  Future<ShiftRow?> myOpenShift(String userId) async {
    final rows = await _client.from('register_shifts').select('*, cash_registers(name)').eq('opened_by', userId).eq('status', 'open').limit(1);
    return rows.isEmpty ? null : ShiftRow.fromJson(rows.first);
  }

  Future<List<ShiftRow>> shifts({int limit = 40}) async {
    final rows = await _client.from('register_shifts').select('*, cash_registers(name)').order('opened_at', ascending: false).limit(limit);
    return [for (final r in rows) ShiftRow.fromJson(r)];
  }

  Future<Map<String, dynamic>> openShift(Map<String, dynamic> p) async => asMap(await _client.rpc('open_shift', params: {'p': p}));

  Future<CashSummary> shiftSummary(String id) async => CashSummary(asMap(await _client.rpc('shift_summary', params: {'p_shift': id})));

  Future<Map<String, dynamic>> closeShift(Map<String, dynamic> p) async => asMap(await _client.rpc('close_shift', params: {'p': p}));

  Future<void> entry(Map<String, dynamic> p) => _client.rpc('create_account_entry', params: {'p': p});

  Future<List<AccountBalance>> balances() async {
    final res = await _client.rpc('account_balances');
    return [
      for (final r in asRows(res))
        AccountBalance(id: r['id'] as String, name: r['name'] as String, type: r['account_type'] as String, accountNo: r['account_no'] as String?, balance: dbl(r['balance']))
    ];
  }

  Future<Statement> statement(String accountId, DateTime from, DateTime to) async {
    final res = asMap(await _client.rpc('account_statement', params: {'p_account': accountId, 'p_from': Fmt.iso(from), 'p_to': Fmt.iso(to)}));
    return Statement(
      name: asMap(res['account'])['name'] as String,
      opening: dbl(res['opening']),
      closing: dbl(res['closing']),
      totalIn: dbl(res['total_in']),
      totalOut: dbl(res['total_out']),
      rows: [
        for (final r in asRows(res['rows']))
          StatementRow(
            date: parseDate(r['date']) ?? DateTime.now(),
            direction: r['direction'] as String,
            amount: dbl(r['amount']),
            source: (r['source_type'] as String?) ?? '',
            description: (r['description'] as String?) ?? '',
            balance: dbl(r['balance']),
          )
      ],
    );
  }

  Future<Map<String, dynamic>> dayPreview(DateTime date) async =>
      asMap(await _client.rpc('day_closing_preview', params: {'p_branch': null, 'p_date': Fmt.iso(date)}));

  Future<Map<String, dynamic>> closeDay(Map<String, dynamic> p) async => asMap(await _client.rpc('close_day', params: {'p': p}));

  Future<void> reopenDay(String id, String reason) => _client.rpc('reopen_day_closing', params: {'p_id': id, 'p_reason': reason});

  Future<List<DayClosingRow>> closings() async {
    final rows = await _client.from('day_closings').select().order('closing_date', ascending: false).order('closed_at', ascending: false).limit(60);
    return [for (final r in rows) DayClosingRow.fromJson(r)];
  }

  Future<void> saveRegister(Map<String, dynamic> p) => _client.rpc('save_register', params: {'p': p});
}

final cashRepoProvider = Provider<CashRepository>((ref) => CashRepository(ref.watch(supabaseProvider)));

final registersProvider = FutureProvider.autoDispose<List<RegisterRow>>((ref) => ref.watch(cashRepoProvider).registers());

final myShiftProvider = FutureProvider.autoDispose<ShiftRow?>((ref) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) return null;
  return ref.watch(cashRepoProvider).myOpenShift(uid);
});

final shiftsProvider = FutureProvider.autoDispose<List<ShiftRow>>((ref) => ref.watch(cashRepoProvider).shifts());

final shiftSummaryProvider =
    FutureProvider.autoDispose.family<CashSummary, String>((ref, id) => ref.watch(cashRepoProvider).shiftSummary(id));

final accountBalancesProvider = FutureProvider.autoDispose<List<AccountBalance>>((ref) => ref.watch(cashRepoProvider).balances());

typedef StatementQuery = ({String accountId, DateTime from, DateTime to});

final statementProvider =
    FutureProvider.autoDispose.family<Statement, StatementQuery>((ref, q) => ref.watch(cashRepoProvider).statement(q.accountId, q.from, q.to));

final dayPreviewProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, DateTime>((ref, d) => ref.watch(cashRepoProvider).dayPreview(d));

final dayClosingsProvider = FutureProvider.autoDispose<List<DayClosingRow>>((ref) => ref.watch(cashRepoProvider).closings());
