import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/date_range_bar.dart';

const kFrequencyLabels = {
  'weekly': 'Weekly',
  'biweekly': 'Every 2 weeks',
  'monthly': 'Monthly',
  'custom': 'Custom dates',
};

class InstallmentPlanRow {
  const InstallmentPlanRow({
    required this.id,
    required this.planNo,
    required this.saleId,
    required this.invoiceNo,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.status,
    required this.productTotal,
    required this.downPayment,
    required this.financed,
    required this.serviceCharge,
    required this.totalPayable,
    required this.paid,
    required this.outstanding,
    required this.count,
    required this.frequency,
    this.nextDueDate,
    this.nextDueAmount = 0,
    this.overdueAmount = 0,
    this.overdueCount = 0,
    this.overdueDays = 0,
    this.remindersEnabled = true,
    this.returned = 0,
    this.terms,
    required this.createdAt,
  });

  final String id;
  final String planNo;
  final String saleId;
  final String invoiceNo;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String status;
  final double productTotal;
  final double downPayment;
  final double financed;
  final double serviceCharge;
  final double totalPayable;
  final double paid;
  final double outstanding;
  final int count;
  final String frequency;
  final DateTime? nextDueDate;
  final double nextDueAmount;
  final double overdueAmount;
  final int overdueCount;
  final int overdueDays;
  final bool remindersEnabled;

  /// Value of goods returned on this sale that was taken off the unpaid schedule.
  final double returned;
  final String? terms;
  final DateTime createdAt;

  bool get isActive => status == 'active';
  bool get isOverdue => overdueAmount > 0.004;

  factory InstallmentPlanRow.fromJson(Map<String, dynamic> j) => InstallmentPlanRow(
        id: j['id'] as String,
        planNo: j['plan_no'] as String,
        saleId: j['sale_id'] as String,
        invoiceNo: (j['invoice_no'] as String?) ?? '',
        customerId: j['customer_id'] as String,
        customerName: (j['customer_name'] as String?) ?? '',
        customerPhone: j['customer_phone'] as String?,
        status: j['status'] as String,
        productTotal: dbl(j['product_total']),
        downPayment: dbl(j['down_payment']),
        financed: dbl(j['financed_amount']),
        serviceCharge: dbl(j['service_charge']),
        totalPayable: dbl(j['total_payable']),
        paid: dbl(j['paid_amount']),
        outstanding: dbl(j['outstanding']),
        count: intOf(j['installment_count']),
        frequency: (j['frequency'] as String?) ?? 'monthly',
        nextDueDate: parseDate(j['next_due_date']),
        nextDueAmount: dbl(j['next_due_amount']),
        overdueAmount: dbl(j['overdue_amount']),
        overdueCount: intOf(j['overdue_count']),
        overdueDays: intOf(j['overdue_days']),
        remindersEnabled: j['reminders_enabled'] != false,
        returned: dbl(j['returned_amount']),
        terms: j['terms'] as String?,
        createdAt: parseDate(j['created_at']) ?? DateTime.now(),
      );
}

class InstallmentItem {
  const InstallmentItem({
    required this.id,
    required this.seq,
    required this.dueDate,
    required this.originalDueDate,
    required this.amount,
    required this.paid,
    required this.status,
  });

  final String id;
  final int seq;
  final DateTime dueDate;
  final DateTime originalDueDate;
  final double amount;
  final double paid;
  final String status;

  double get remaining => (amount - paid).clamp(0, double.infinity).toDouble();
  bool get isOpen => status == 'pending' || status == 'partial';
  bool get rescheduled => dueDate != originalDueDate;

  bool isOverdueOn(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    return isOpen && DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(t);
  }

  factory InstallmentItem.fromJson(Map<String, dynamic> j) => InstallmentItem(
        id: j['id'] as String,
        seq: intOf(j['seq']),
        dueDate: _dateOnly(j['due_date']),
        originalDueDate: _dateOnly(j['original_due_date']),
        amount: dbl(j['amount']),
        paid: dbl(j['paid_amount']),
        status: j['status'] as String,
      );
}

DateTime _dateOnly(dynamic v) {
  final s = v?.toString() ?? '';
  final d = DateTime.tryParse(s);
  if (d == null) return DateTime.now();
  return DateTime(d.year, d.month, d.day);
}

/// One row of the due list: an unpaid installment with its customer and plan.
class InstallmentDue {
  const InstallmentDue({
    required this.itemId,
    required this.planId,
    required this.planNo,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.seq,
    required this.dueDate,
    required this.remaining,
    required this.status,
    required this.daysOverdue,
  });

  final String itemId;
  final String planId;
  final String planNo;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final int seq;
  final DateTime dueDate;
  final double remaining;
  final String status;
  final int daysOverdue;

  bool get isOverdue => daysOverdue > 0;

  factory InstallmentDue.fromJson(Map<String, dynamic> j) => InstallmentDue(
        itemId: j['id'] as String,
        planId: j['plan_id'] as String,
        planNo: (j['plan_no'] as String?) ?? '',
        customerId: j['customer_id'] as String,
        customerName: (j['customer_name'] as String?) ?? '',
        customerPhone: j['customer_phone'] as String?,
        seq: intOf(j['seq']),
        dueDate: _dateOnly(j['due_date']),
        remaining: dbl(j['remaining']),
        status: j['status'] as String,
        daysOverdue: intOf(j['days_overdue']),
      );
}

class InstallmentPayment {
  const InstallmentPayment({
    required this.id,
    required this.receiptNo,
    required this.amount,
    required this.allocated,
    required this.accountName,
    required this.date,
    this.reference,
    this.note,
  });

  final String id;
  final String receiptNo;
  final double amount;
  final double allocated;
  final String accountName;
  final DateTime date;
  final String? reference;
  final String? note;

  double get advance => amount - allocated;

  factory InstallmentPayment.fromJson(Map<String, dynamic> j) => InstallmentPayment(
        id: j['id'] as String,
        receiptNo: j['receipt_no'] as String,
        amount: dbl(j['amount']),
        allocated: dbl(j['allocated_amount']),
        accountName: (j['payment_accounts'] as Map?)?['name'] as String? ?? 'Payment',
        date: parseDate(j['payment_date']) ?? DateTime.now(),
        reference: j['reference'] as String?,
        note: j['note'] as String?,
      );
}

class Guarantor {
  const Guarantor({this.id, this.kind = 'guarantor', required this.name, this.phone, this.address, this.relationship, this.nid});

  final String? id;
  final String kind;
  final String name;
  final String? phone;
  final String? address;
  final String? relationship;
  final String? nid;

  Map<String, dynamic> toPayload() => {
        'kind': kind,
        'name': name,
        'phone': phone,
        'address': address,
        'relationship': relationship,
        'nid_number': nid,
      };

  factory Guarantor.fromJson(Map<String, dynamic> j) => Guarantor(
        id: j['id'] as String?,
        kind: (j['kind'] as String?) ?? 'guarantor',
        name: j['name'] as String,
        phone: j['phone'] as String?,
        address: j['address'] as String?,
        relationship: j['relationship'] as String?,
        nid: j['nid_number'] as String?,
      );
}

class Followup {
  const Followup({
    required this.id,
    required this.planId,
    required this.dueDate,
    required this.note,
    required this.status,
    this.outcome,
    this.customerName,
    this.planNo,
  });

  final String id;
  final String planId;
  final DateTime dueDate;
  final String note;
  final String status;
  final String? outcome;
  final String? customerName;
  final String? planNo;

  bool get isOpen => status == 'open';

  factory Followup.fromJson(Map<String, dynamic> j) => Followup(
        id: j['id'] as String,
        planId: j['plan_id'] as String,
        dueDate: _dateOnly(j['due_date']),
        note: j['note'] as String,
        status: j['status'] as String,
        outcome: j['outcome'] as String?,
        customerName: (j['customers'] as Map?)?['name'] as String?,
        planNo: (j['installment_plans'] as Map?)?['plan_no'] as String?,
      );
}

class DateChange {
  const DateChange({required this.seq, required this.oldDate, required this.newDate, required this.reason, required this.at});

  final int seq;
  final DateTime oldDate;
  final DateTime newDate;
  final String reason;
  final DateTime at;
}

class ReminderLogEntry {
  const ReminderLogEntry({required this.kind, required this.channel, required this.at, this.message});

  final String kind;
  final String channel;
  final DateTime at;
  final String? message;
}

class PlanDetail {
  const PlanDetail({
    required this.plan,
    required this.items,
    required this.payments,
    required this.guarantors,
    required this.followups,
    required this.dateChanges,
    required this.reminders,
  });

  final InstallmentPlanRow plan;
  final List<InstallmentItem> items;
  final List<InstallmentPayment> payments;
  final List<Guarantor> guarantors;
  final List<Followup> followups;
  final List<DateChange> dateChanges;
  final List<ReminderLogEntry> reminders;
}

class InstallmentSummary {
  const InstallmentSummary(this.raw);

  final Map<String, dynamic> raw;

  int get dueTodayCount => intOf(raw['due_today_count']);
  double get dueTodayAmount => dbl(raw['due_today_amount']);
  int get overdueCount => intOf(raw['overdue_count']);
  double get overdueAmount => dbl(raw['overdue_amount']);
  int get next7Count => intOf(raw['next7_count']);
  double get next7Amount => dbl(raw['next7_amount']);
  int get activePlans => intOf(raw['active_plans']);
  double get outstanding => dbl(raw['outstanding']);
  double get collectedToday => dbl(raw['collected_today']);
  double get collectedMonth => dbl(raw['collected_month']);
  int get followupsDue => intOf(raw['followups_due']);
}

class ReminderRow {
  const ReminderRow({
    required this.itemId,
    required this.planId,
    required this.planNo,
    required this.customerId,
    required this.customerName,
    this.phone,
    required this.amount,
    required this.dueDate,
    required this.kind,
    required this.daysOverdue,
    required this.message,
  });

  final String itemId;
  final String planId;
  final String planNo;
  final String customerId;
  final String customerName;
  final String? phone;
  final double amount;
  final DateTime dueDate;
  final String kind;
  final int daysOverdue;
  final String message;

  factory ReminderRow.fromJson(Map<String, dynamic> j) => ReminderRow(
        itemId: j['item_id'] as String,
        planId: j['plan_id'] as String,
        planNo: (j['plan_no'] as String?) ?? '',
        customerId: j['customer_id'] as String,
        customerName: (j['customer_name'] as String?) ?? '',
        phone: j['phone'] as String?,
        amount: dbl(j['amount']),
        dueDate: _dateOnly(j['due_date']),
        kind: j['kind'] as String,
        daysOverdue: intOf(j['days_overdue']),
        message: (j['message'] as String?) ?? '',
      );
}

/// due list scopes
enum DueScope { today, week, fortnight, month, overdue }

typedef PlanQuery = ({String status, String search, String? customerId, int limit});
typedef DueQuery = ({DueScope scope, String? customerId});
typedef ReportQuery = ({DateRange range});

class InstallmentsRepository {
  InstallmentsRepository(this._client);

  final SupabaseClient _client;

  Future<List<InstallmentPlanRow>> plans(PlanQuery q) async {
    var query = _client.from('installment_plans_view').select();
    if (q.status == 'overdue') {
      query = query.eq('status', 'active').gt('overdue_amount', 0);
    } else if (q.status != 'all') {
      query = query.eq('status', q.status);
    }
    if (q.customerId != null) query = query.eq('customer_id', q.customerId!);
    final s = safeSearch(q.search);
    if (s.isNotEmpty) query = query.or('plan_no.ilike.%$s%,customer_name.ilike.%$s%,customer_phone.ilike.%$s%,invoice_no.ilike.%$s%');
    final rows = await query.order('created_at', ascending: false).limit(q.limit);
    return [for (final r in rows) InstallmentPlanRow.fromJson(r)];
  }

  Future<List<InstallmentDue>> dues(DueQuery q) async {
    final today = DateTime.now();
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    var query = _client
        .from('installment_items_view')
        .select()
        .eq('plan_status', 'active')
        .or('status.eq.pending,status.eq.partial');
    if (q.customerId != null) query = query.eq('customer_id', q.customerId!);
    final t = DateTime(today.year, today.month, today.day);
    switch (q.scope) {
      case DueScope.today:
        query = query.eq('due_date', iso(t));
      case DueScope.week:
        query = query.gte('due_date', iso(t)).lte('due_date', iso(t.add(const Duration(days: 7))));
      case DueScope.fortnight:
        query = query.gte('due_date', iso(t)).lte('due_date', iso(t.add(const Duration(days: 15))));
      case DueScope.month:
        query = query.gte('due_date', iso(t)).lte('due_date', iso(t.add(const Duration(days: 30))));
      case DueScope.overdue:
        query = query.lt('due_date', iso(t));
    }
    final rows = await query.order('due_date').limit(300);
    return [for (final r in rows) InstallmentDue.fromJson(r)];
  }

  Future<PlanDetail> detail(String id) async {
    final planRow = await _client.from('installment_plans_view').select().eq('id', id).single();
    final items = await _client.from('installment_items').select().eq('plan_id', id).order('seq');
    final pays = await _client
        .from('installment_payments')
        .select('*, payment_accounts(name)')
        .eq('plan_id', id)
        .order('payment_date', ascending: false);
    final guarantors = await _client.from('installment_guarantors').select().eq('plan_id', id);
    final followups = await _client.from('installment_followups').select().eq('plan_id', id).order('due_date', ascending: false);
    final changes = await _client
        .from('installment_date_changes')
        .select('*, installment_items(seq)')
        .eq('plan_id', id)
        .order('changed_at', ascending: false);
    final logs = await _client.from('installment_reminder_log').select().eq('plan_id', id).order('sent_at', ascending: false).limit(20);
    return PlanDetail(
      plan: InstallmentPlanRow.fromJson(planRow),
      items: [for (final r in items) InstallmentItem.fromJson(r)],
      payments: [for (final r in pays) InstallmentPayment.fromJson(r)],
      guarantors: [for (final r in guarantors) Guarantor.fromJson(r)],
      followups: [for (final r in followups) Followup.fromJson(r)],
      dateChanges: [
        for (final r in changes)
          DateChange(
            seq: intOf((r['installment_items'] as Map?)?['seq']),
            oldDate: _dateOnly(r['old_date']),
            newDate: _dateOnly(r['new_date']),
            reason: (r['reason'] as String?) ?? '',
            at: parseDate(r['changed_at']) ?? DateTime.now(),
          )
      ],
      reminders: [
        for (final r in logs)
          ReminderLogEntry(
            kind: r['kind'] as String,
            channel: r['channel'] as String,
            at: parseDate(r['sent_at']) ?? DateTime.now(),
            message: r['message'] as String?,
          )
      ],
    );
  }

  Future<List<Followup>> openFollowups() async {
    final rows = await _client
        .from('installment_followups')
        .select('*, customers(name), installment_plans(plan_no)')
        .eq('status', 'open')
        .order('due_date')
        .limit(100);
    return [for (final r in rows) Followup.fromJson(r)];
  }

  Future<InstallmentSummary> summary() async {
    final res = await _client.rpc('installment_summary', params: {'p_branch': null});
    return InstallmentSummary(asMap(res));
  }

  Future<List<ReminderRow>> reminders() async {
    final res = await _client.rpc('installment_reminders', params: {'p_date': null});
    return [for (final r in asRows(res)) ReminderRow.fromJson(r)];
  }

  Future<Map<String, dynamic>> report(DateRange range) async {
    final res = await _client.rpc('installment_report', params: {'p_from': range.fromIso, 'p_to': range.toIso, 'p_branch': null});
    return asMap(res);
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> payload) async =>
      asMap(await _client.rpc('create_installment_sale', params: {'p': payload}));

  Future<Map<String, dynamic>> collect(Map<String, dynamic> payload) async =>
      asMap(await _client.rpc('collect_installment', params: {'p': payload}));

  Future<void> reschedule(String itemId, DateTime date, String reason) => _client.rpc('reschedule_installment', params: {
        'p_item': itemId,
        'p_new_date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'p_reason': reason,
      });

  Future<void> addFollowup(Map<String, dynamic> payload) => _client.rpc('add_installment_followup', params: {'p': payload});

  Future<void> completeFollowup(String id, String? outcome) =>
      _client.rpc('complete_installment_followup', params: {'p_id': id, 'p_outcome': outcome});

  Future<void> logReminder(Map<String, dynamic> payload) => _client.rpc('log_installment_reminder', params: {'p': payload});

  Future<void> setReminders(String planId, bool enabled) =>
      _client.rpc('set_installment_reminders', params: {'p_plan': planId, 'p_enabled': enabled});
}

final installmentsRepoProvider = Provider<InstallmentsRepository>((ref) => InstallmentsRepository(ref.watch(supabaseProvider)));

final installmentPlansProvider =
    FutureProvider.autoDispose.family<List<InstallmentPlanRow>, PlanQuery>((ref, q) => ref.watch(installmentsRepoProvider).plans(q));

final installmentDuesProvider =
    FutureProvider.autoDispose.family<List<InstallmentDue>, DueQuery>((ref, q) => ref.watch(installmentsRepoProvider).dues(q));

final planDetailProvider =
    FutureProvider.autoDispose.family<PlanDetail, String>((ref, id) => ref.watch(installmentsRepoProvider).detail(id));

final installmentSummaryProvider =
    FutureProvider.autoDispose<InstallmentSummary>((ref) => ref.watch(installmentsRepoProvider).summary());

final installmentRemindersProvider =
    FutureProvider.autoDispose<List<ReminderRow>>((ref) => ref.watch(installmentsRepoProvider).reminders());

final openFollowupsProvider = FutureProvider.autoDispose<List<Followup>>((ref) => ref.watch(installmentsRepoProvider).openFollowups());

final installmentReportProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, DateRange>((ref, r) => ref.watch(installmentsRepoProvider).report(r));

/// The installment plan created with a sale, if any.
final planForSaleProvider = FutureProvider.autoDispose.family<String?, String>((ref, saleId) async {
  final rows = await ref.watch(supabaseProvider).from('installment_plans').select('id').eq('sale_id', saleId).limit(1);
  return rows.isEmpty ? null : rows.first['id'] as String;
});
