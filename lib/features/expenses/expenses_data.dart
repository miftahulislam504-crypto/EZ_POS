import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/date_range_bar.dart';

class ExpenseRow {
  const ExpenseRow({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.status,
    this.categoryId,
    this.categoryName,
    this.accountName,
    this.paidBy,
    this.note,
    this.isRecurring = false,
    this.recurrence,
    this.voidReason,
  });

  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final String status;
  final String? categoryId;
  final String? categoryName;
  final String? accountName;
  final String? paidBy;
  final String? note;
  final bool isRecurring;
  final String? recurrence;
  final String? voidReason;

  bool get isVoid => status == 'void';

  factory ExpenseRow.fromJson(Map<String, dynamic> j) => ExpenseRow(
        id: j['id'] as String,
        title: j['title'] as String,
        amount: dbl(j['amount']),
        date: parseDate(j['expense_date']) ?? DateTime.now(),
        status: j['status'] as String,
        categoryId: j['category_id'] as String?,
        categoryName: (j['expense_categories'] as Map?)?['name'] as String?,
        accountName: (j['payment_accounts'] as Map?)?['name'] as String?,
        paidBy: j['paid_by'] as String?,
        note: j['note'] as String?,
        isRecurring: j['is_recurring'] == true,
        recurrence: j['recurrence'] as String?,
        voidReason: j['void_reason'] as String?,
      );
}

typedef ExpenseQuery = ({DateRange range, String? categoryId});

class ExpenseSummary {
  const ExpenseSummary(this.rows);

  final List<ExpenseRow> rows;

  double get total => rows.where((r) => !r.isVoid).fold(0, (s, r) => s + r.amount);

  Map<String, double> get byCategory {
    final m = <String, double>{};
    for (final r in rows.where((r) => !r.isVoid)) {
      final k = r.categoryName ?? 'Uncategorised';
      m[k] = (m[k] ?? 0) + r.amount;
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

class ExpenseRepository {
  ExpenseRepository(this._client);

  final SupabaseClient _client;

  Future<ExpenseSummary> list(ExpenseQuery q) async {
    var query = _client
        .from('expenses')
        .select('*, expense_categories(name), payment_accounts(name)')
        .gte('expense_date', q.range.fromIso)
        .lte('expense_date', q.range.toIso);
    if (q.categoryId != null) query = query.eq('category_id', q.categoryId!);
    final rows = await query.order('expense_date', ascending: false).order('created_at', ascending: false).limit(500);
    return ExpenseSummary([for (final r in rows) ExpenseRow.fromJson(r)]);
  }

  Future<void> create(Map<String, dynamic> payload) => _client.rpc('create_expense', params: {'p': payload});

  Future<void> voidExpense(String id, String reason) => _client.rpc('void_expense', params: {'p_id': id, 'p_reason': reason});
}

final expenseRepoProvider = Provider<ExpenseRepository>((ref) => ExpenseRepository(ref.watch(supabaseProvider)));

final expensesProvider = FutureProvider.autoDispose.family<ExpenseSummary, ExpenseQuery>((ref, q) {
  return ref.watch(expenseRepoProvider).list(q);
});
