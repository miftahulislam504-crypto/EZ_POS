import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';
import '../inventory/inventory_data.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.sales,
    required this.invoices,
    required this.purchases,
    required this.returns,
    required this.expenses,
    required this.collected,
    required this.customerDue,
    required this.supplierPayable,
    required this.products,
    required this.lowStock,
    required this.outOfStock,
    required this.canViewProfit,
    this.profit,
    this.stockValue,
  });

  final double sales;
  final int invoices;
  final double purchases;
  final double returns;
  final double expenses;
  final double collected;
  final double customerDue;
  final double supplierPayable;
  final int products;
  final int lowStock;
  final int outOfStock;
  final bool canViewProfit;
  final double? profit;
  final double? stockValue;

  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
        sales: dbl(j['sales']),
        invoices: intOf(j['invoices']),
        purchases: dbl(j['purchases']),
        returns: dbl(j['returns']),
        expenses: dbl(j['expenses']),
        collected: dbl(j['collected']),
        customerDue: dbl(j['customer_due']),
        supplierPayable: dbl(j['supplier_payable']),
        products: intOf(j['products']),
        lowStock: intOf(j['low_stock']),
        outOfStock: intOf(j['out_of_stock']),
        canViewProfit: j['can_view_profit'] == true,
        profit: dblOrNull(j['profit']),
        stockValue: dblOrNull(j['stock_value']),
      );
}

class TrendPoint {
  const TrendPoint({required this.day, required this.sales, required this.invoices, this.profit});

  final DateTime day;
  final double sales;
  final int invoices;
  final double? profit;
}

class TopItem {
  const TopItem({required this.name, required this.quantity, required this.revenue});

  final String name;
  final double quantity;
  final double revenue;
}

final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final res = await ref.watch(supabaseProvider).rpc('dashboard_summary', params: {'p_branch': null});
  return DashboardSummary.fromJson(asMap(res));
});

String _isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Last [days] days including today.
final salesTrendProvider = FutureProvider.autoDispose.family<List<TrendPoint>, int>((ref, days) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
  final res = await ref.watch(supabaseProvider).rpc('sales_trend', params: {'p_from': _isoDay(from), 'p_to': _isoDay(now), 'p_branch': null});
  return [
    for (final r in asRows(res))
      TrendPoint(day: DateTime.parse(r['day'] as String), sales: dbl(r['sales']), invoices: intOf(r['invoices']), profit: dblOrNull(r['profit']))
  ];
});

Future<List<TopItem>> _top(Ref ref, String fn, int days) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
  final res = await ref.watch(supabaseProvider).rpc(fn, params: {'p_from': _isoDay(from), 'p_to': _isoDay(now), 'p_branch': null, 'p_limit': 5});
  return [for (final r in asRows(res)) TopItem(name: r['name'] as String, quantity: dbl(r['quantity']), revenue: dbl(r['revenue']))];
}

final topProductsProvider = FutureProvider.autoDispose.family<List<TopItem>, int>((ref, days) => _top(ref, 'top_products', days));
final topCategoriesProvider = FutureProvider.autoDispose.family<List<TopItem>, int>((ref, days) => _top(ref, 'top_categories', days));

final lowStockProvider = FutureProvider.autoDispose<List<StockRow>>((ref) {
  return ref.watch(inventoryRepoProvider).stockReport((filter: 'attention', search: '', limit: 8));
});
