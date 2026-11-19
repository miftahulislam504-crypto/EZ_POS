import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/date_range_bar.dart';

class DailyRow {
  const DailyRow({
    required this.day,
    required this.invoices,
    required this.gross,
    required this.discount,
    required this.tax,
    required this.total,
    required this.returns,
    required this.netSales,
    required this.cogs,
    required this.profit,
    required this.collected,
    required this.creditGiven,
  });

  final DateTime day;
  final int invoices;
  final double gross;
  final double discount;
  final double tax;
  final double total;
  final double returns;
  final double netSales;
  final double cogs;
  final double profit;
  final double collected;
  final double creditGiven;

  factory DailyRow.fromJson(Map<String, dynamic> j) => DailyRow(
        day: DateTime.parse(j['day'] as String),
        invoices: intOf(j['invoices']),
        gross: dbl(j['gross']),
        discount: dbl(j['discount']),
        tax: dbl(j['tax']),
        total: dbl(j['total']),
        returns: dbl(j['returns']),
        netSales: dbl(j['net_sales']),
        cogs: dbl(j['cogs']),
        profit: dbl(j['profit']),
        collected: dbl(j['collected']),
        creditGiven: dbl(j['credit_given']),
      );
}

class DailyReport {
  const DailyReport({required this.rows, required this.methods});

  final List<DailyRow> rows;
  final List<({String name, double amount})> methods;

  double _sum(double Function(DailyRow) f) => rows.fold(0, (s, r) => s + f(r));

  int get invoices => rows.fold(0, (s, r) => s + r.invoices);
  double get total => _sum((r) => r.total);
  double get discount => _sum((r) => r.discount);
  double get tax => _sum((r) => r.tax);
  double get returns => _sum((r) => r.returns);
  double get netSales => _sum((r) => r.netSales);
  double get cogs => _sum((r) => r.cogs);
  double get profit => _sum((r) => r.profit);
  double get collected => _sum((r) => r.collected);
  double get creditGiven => _sum((r) => r.creditGiven);
}

final dailySalesReportProvider = FutureProvider.autoDispose.family<DailyReport, DateRange>((ref, range) async {
  final res = await ref.watch(supabaseProvider).rpc('report_daily_sales', params: {'p_from': range.fromIso, 'p_to': range.toIso, 'p_branch': null});
  final m = asMap(res);
  return DailyReport(
    rows: [for (final r in asRows(m['rows'])) DailyRow.fromJson(r)],
    methods: [for (final r in asRows(m['methods'])) (name: r['name'] as String, amount: dbl(r['amount']))],
  );
});
