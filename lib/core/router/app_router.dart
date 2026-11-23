import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_pages.dart';
import '../../features/customers/customer_detail_page.dart';
import '../../features/customers/customer_form_page.dart';
import '../../features/customers/customers_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/expenses/expenses_page.dart';
import '../../features/cash/accounts_page.dart';
import '../../features/cash/cash_page.dart';
import '../../features/cash/day_closing_page.dart';
import '../../features/installments/installment_report_page.dart';
import '../../features/installments/installments_page.dart';
import '../../features/installments/plan_detail_page.dart';
import '../../features/installments/reminders_page.dart';
import '../../features/inventory/inventory_page.dart';
import '../../features/inventory/serial_lookup_page.dart';
import '../../features/inventory/stock_count_page.dart';
import '../../features/inventory/transfer_detail_page.dart';
import '../../features/inventory/transfer_form_page.dart';
import '../../features/inventory/transfers_page.dart';
import '../../features/pos/pos_page.dart';
import '../../features/products/barcode_labels_page.dart';
import '../../features/products/catalog_page.dart';
import '../../features/products/product_form_page.dart';
import '../../features/purchases/purchase_detail_page.dart';
import '../../features/purchases/purchase_form_page.dart';
import '../../features/purchases/purchase_return_page.dart';
import '../../features/reports/reports_page.dart';
import '../../features/sales/exchange_page.dart';
import '../../features/sales/sale_detail_page.dart';
import '../../features/sales/sale_return_page.dart';
import '../../features/settings/branches_page.dart';
import '../../features/settings/business_settings_pages.dart';
import '../../features/settings/installment_settings_page.dart';
import '../../features/settings/more_page.dart';
import '../../features/settings/printer_settings_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/team_pages.dart';
import '../../features/shell/app_shell.dart';
import '../../features/suppliers/supplier_detail_page.dart';
import '../../features/suppliers/supplier_form_page.dart';
import '../../features/suppliers/suppliers_page.dart';
import '../../features/transactions/transactions_page.dart';
import '../data/providers.dart';
import '../errors.dart';
import '../models/app_user.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

const _publicPaths = {'/login', '/signup'};
const _bootPaths = {'/login', '/signup', '/setup', '/splash'};

/// Route -> permission check. Server-side rules are the real protection; this keeps people out of screens they cannot use.
bool _allowed(String path, AppUser u) {
  bool starts(String p) => path == p || path.startsWith('$p/');
  if (starts('/settings/team') || starts('/settings/roles')) return u.can(Perm.usersManage);
  if (starts('/settings/catalog')) return u.can(Perm.productsManage);
  if (starts('/settings/installments') || starts('/settings/branches')) return u.can(Perm.settingsManage);
  if (starts('/settings/business') || starts('/settings/sales') || starts('/settings/receipt') || starts('/settings/payment-methods') || starts('/settings/product-rules')) {
    return u.can(Perm.settingsManage);
  }
  if (starts('/pos')) return u.can(Perm.salesCreate);
  if (starts('/installments')) return u.can(Perm.installmentsView);
  if (starts('/cash')) return u.canAny([Perm.cashView, Perm.accountsView]);
  if (starts('/inventory/transfers')) return u.can(Perm.transfersView);
  if (starts('/inventory/counts')) return u.can(Perm.inventoryCount);
  if (starts('/dashboard')) return u.can(Perm.dashboardView);
  if (starts('/reports')) return u.can(Perm.reportsView);
  if (starts('/expenses')) return u.can(Perm.expensesView);
  if (starts('/customers')) return u.can(Perm.customersView);
  if (starts('/suppliers')) return u.can(Perm.suppliersView);
  if (starts('/purchases')) return u.can(Perm.purchasesView);
  if (starts('/sales')) return u.can(Perm.salesView);
  if (starts('/products')) return u.can(Perm.productsView);
  if (starts('/inventory')) return u.canAny([Perm.productsView, Perm.inventoryView]);
  return true;
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      transitionsBuilder: (_, animation, __, c) => FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: c),
    );

CustomTransitionPage<void> _slide(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, animation, __, c) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(curved), child: c),
        );
      },
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(userIdProvider, (_, __) => refresh.value++);
  ref.listen(appUserProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  GoRoute full(String path, Widget Function(GoRouterState s) builder) => GoRoute(
        path: path,
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => _slide(state, builder(state)),
      );

  GoRoute tab(String path, Widget child) => GoRoute(path: path, pageBuilder: (context, state) => _fade(state, child));

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      final signedIn = ref.read(userIdProvider) != null;
      if (!signedIn) return _publicPaths.contains(path) ? null : '/login';

      final appUser = ref.read(appUserProvider);
      if (appUser.isLoading && !appUser.hasValue) return path == '/splash' ? null : '/splash';
      if (appUser.hasError) return path == '/splash' ? null : '/splash';
      final user = appUser.valueOrNull;
      if (user == null) return path == '/setup' ? null : '/setup';

      if (_bootPaths.contains(path) || path == '/') return user.can(Perm.dashboardView) ? '/dashboard' : (user.can(Perm.salesCreate) ? '/pos' : '/more');
      if (!_allowed(path, user)) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/signup', builder: (_, __) => const SignUpPage()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupPage()),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          tab('/dashboard', const DashboardPage()),
          tab('/pos', const PosPage()),
          tab('/transactions', const TransactionsPage()),
          tab('/inventory', const InventoryPage()),
          tab('/installments', const InstallmentsPage()),
          tab('/cash', const CashPage()),
          tab('/more', const MorePage()),
          tab('/customers', const CustomersPage()),
          tab('/suppliers', const SuppliersPage()),
          tab('/expenses', const ExpensesPage()),
          tab('/reports', const ReportsPage()),
          tab('/settings', const SettingsPage()),
        ],
      ),
      full('/settings/business', (_) => const BusinessProfilePage()),
      full('/settings/sales', (_) => const SalesSettingsPage()),
      full('/settings/receipt', (_) => const ReceiptSettingsPage()),
      full('/settings/product-rules', (_) => const ProductRulesPage()),
      full('/settings/printer', (_) => const PrinterSettingsPage()),
      full('/settings/payment-methods', (_) => const PaymentMethodsPage()),
      full('/settings/catalog', (_) => const CatalogPage()),
      full('/settings/team', (_) => const TeamPage()),
      full('/settings/roles', (_) => const RolesPage()),
      full('/settings/installments', (_) => const InstallmentSettingsPage()),
      full('/settings/branches', (_) => const BranchesPage()),
      full('/installments/reminders', (_) => const RemindersPage()),
      full('/installments/report', (_) => const InstallmentReportPage()),
      full('/installments/:id', (s) => PlanDetailPage(planId: s.pathParameters['id']!)),
      full('/inventory/transfers', (_) => const TransfersPage()),
      full('/inventory/transfers/new', (_) => const TransferFormPage()),
      full('/inventory/transfers/:id', (s) => TransferDetailPage(transferId: s.pathParameters['id']!)),
      full('/inventory/counts', (_) => const StockCountsPage()),
      full('/inventory/counts/new', (_) => const StockCountPage()),
      full('/inventory/counts/:id', (s) => StockCountPage(countId: s.pathParameters['id'])),
      full('/inventory/serials', (s) => SerialLookupPage(initial: s.uri.queryParameters['q'])),
      full('/inventory/expiry', (_) => const ExpiryPage()),
      full('/cash/day-closing', (_) => const DayClosingPage()),
      full('/cash/accounts', (_) => const AccountsPage()),
      full('/cash/accounts/:id', (s) => AccountStatementPage(accountId: s.pathParameters['id']!)),
      full('/purchases/:id/return', (s) => PurchaseReturnPage(purchaseId: s.pathParameters['id']!)),
      full('/sales/:id/exchange', (s) => ExchangePage(saleId: s.pathParameters['id']!)),
      full('/products/new', (_) => const ProductFormPage()),
      full('/products/labels', (s) => BarcodeLabelsPage(initialProductId: s.uri.queryParameters['product'])),
      full('/products/:id/edit', (s) => ProductFormPage(productId: s.pathParameters['id'])),
      full('/customers/new', (_) => const CustomerFormPage()),
      full('/customers/:id', (s) => CustomerDetailPage(customerId: s.pathParameters['id']!)),
      full('/customers/:id/edit', (s) => CustomerFormPage(customerId: s.pathParameters['id'])),
      full('/suppliers/new', (_) => const SupplierFormPage()),
      full('/suppliers/:id', (s) => SupplierDetailPage(supplierId: s.pathParameters['id']!)),
      full('/suppliers/:id/edit', (s) => SupplierFormPage(supplierId: s.pathParameters['id'])),
      full('/purchases/new', (s) => PurchaseFormPage(supplierId: s.uri.queryParameters['supplier'])),
      full('/purchases/:id', (s) => PurchaseDetailPage(purchaseId: s.pathParameters['id']!)),
      full('/sales/:id', (s) => SaleDetailPage(saleId: s.pathParameters['id']!)),
      full('/sales/:id/return', (s) => SaleReturnPage(saleId: s.pathParameters['id']!)),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: EmptyState(icon: Icons.explore_off_outlined, title: 'Page not found', message: state.uri.toString(), actionLabel: 'Go home', onAction: () => context.go('/dashboard')),
    ),
  );
});

class _SplashPage extends ConsumerWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUserProvider);
    return Scaffold(
      body: Center(
        child: state.hasError
            ? ErrorState(
                message: friendlyError(state.error!),
                onRetry: () => ref.invalidate(appUserProvider),
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(size: 64),
                  SizedBox(height: 28),
                  SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
                ],
              ),
      ),
      bottomNavigationBar: state.hasError
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton('Sign out', kind: ButtonKind.secondary, expand: true, onPressed: () => ref.read(supabaseProvider).auth.signOut()),
              ),
            )
          : null,
    );
  }
}
