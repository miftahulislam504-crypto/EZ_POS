import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/customers/customers_data.dart';
import '../../features/dashboard/dashboard_data.dart';
import '../../features/expenses/expenses_data.dart';
import '../../features/inventory/inventory_data.dart';
import '../../features/products/products_data.dart';
import '../../features/purchases/purchases_data.dart';
import '../../features/reports/reports_data.dart';
import '../../features/sales/sales_data.dart';
import '../../features/suppliers/suppliers_data.dart';
import '../../features/transactions/payments_data.dart';
import 'common_data.dart';

/// Call after anything that changes money, stock or balances so every screen shows fresh figures.
void refreshAfterTransaction(WidgetRef ref) {
  final providers = <ProviderOrFamily>[
    dashboardSummaryProvider,
    salesTrendProvider,
    topProductsProvider,
    topCategoriesProvider,
    lowStockProvider,
    salesListProvider,
    saleDetailProvider,
    salesReturnsProvider,
    customersProvider,
    customerProvider,
    customerLedgerProvider,
    customerSummaryProvider,
    suppliersProvider,
    supplierProvider,
    supplierLedgerProvider,
    supplierSummaryProvider,
    purchasesListProvider,
    purchaseDetailProvider,
    productsProvider,
    productByIdProvider,
    stockReportProvider,
    stockMovementsProvider,
    expensesProvider,
    dailySalesReportProvider,
    customerPaymentsProvider,
    supplierPaymentsProvider,
    paymentAccountsProvider,
  ];
  for (final p in providers) {
    ref.invalidate(p);
  }
}
