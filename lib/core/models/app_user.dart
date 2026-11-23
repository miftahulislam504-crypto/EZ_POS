/// Permission keys. They mirror app.default_permissions() in the database.
class Perm {
  Perm._();

  static const dashboardView = 'dashboard.view';
  static const salesView = 'sales.view';
  static const salesCreate = 'sales.create';
  static const salesDiscount = 'sales.discount';
  static const salesDue = 'sales.due';
  static const salesVoid = 'sales.void';
  static const returnsCreate = 'returns.create';
  static const customersView = 'customers.view';
  static const customersManage = 'customers.manage';
  static const customersPayment = 'customers.payment';
  static const suppliersView = 'suppliers.view';
  static const suppliersManage = 'suppliers.manage';
  static const suppliersPayment = 'suppliers.payment';
  static const purchasesView = 'purchases.view';
  static const purchasesCreate = 'purchases.create';
  static const productsView = 'products.view';
  static const productsManage = 'products.manage';
  static const inventoryView = 'inventory.view';
  static const inventoryAdjust = 'inventory.adjust';
  static const expensesView = 'expenses.view';
  static const expensesCreate = 'expenses.create';
  static const expensesVoid = 'expenses.void';
  static const reportsView = 'reports.view';
  static const settingsManage = 'settings.manage';
  static const usersManage = 'users.manage';
  static const installmentsView = 'installments.view';
  static const installmentsCreate = 'installments.create';
  static const installmentsCollect = 'installments.collect';
  static const installmentsReschedule = 'installments.reschedule';
  static const installmentsManage = 'installments.manage';
  static const transfersView = 'transfers.view';
  static const transfersManage = 'transfers.manage';
  static const purchasesReturn = 'purchases.return';
  static const inventoryCount = 'inventory.count';
  static const cashView = 'cash.view';
  static const cashShift = 'cash.shift';
  static const cashCloseDay = 'cash.close_day';
  static const cashReopen = 'cash.reopen';
  static const accountsView = 'accounts.view';
  static const accountsManage = 'accounts.manage';
  static const customersDocuments = 'customers.documents';
  static const returnsOverrideWindow = 'returns.override_window';

  /// Grouped for the role editor: group title -> (key, label).
  static const Map<String, List<(String, String)>> groups = {
    'Dashboard and reports': [
      (dashboardView, 'View dashboard'),
      (reportsView, 'View reports and profit'),
    ],
    'Sales': [
      (salesView, 'View sales'),
      (salesCreate, 'Create sales (POS)'),
      (salesDiscount, 'Give discounts and change prices'),
      (salesDue, 'Sell on credit (due sale)'),
      (salesVoid, 'Void sales'),
      (returnsCreate, 'Create sales returns'),
      (returnsOverrideWindow, 'Approve returns after the return period'),
    ],
    'Customers': [
      (customersView, 'View customers'),
      (customersManage, 'Add and edit customers'),
      (customersPayment, 'Receive customer payments'),
    ],
    'Suppliers and purchases': [
      (suppliersView, 'View suppliers'),
      (suppliersManage, 'Add and edit suppliers'),
      (suppliersPayment, 'Make supplier payments'),
      (purchasesView, 'View purchases'),
      (purchasesCreate, 'Create purchases'),
    ],
    'Products and stock': [
      (productsView, 'View products'),
      (productsManage, 'Add and edit products'),
      (inventoryView, 'View stock'),
      (inventoryAdjust, 'Adjust stock'),
    ],
    'Installments': [
      (installmentsView, 'View installment plans'),
      (installmentsCreate, 'Sell on installment'),
      (installmentsCollect, 'Collect installments and follow up'),
      (installmentsReschedule, 'Change installment due dates'),
      (installmentsManage, 'Manage installment settings and reminders'),
    ],
    'Stock transfers and counts': [
      (transfersView, 'View stock transfers'),
      (transfersManage, 'Create, send and receive transfers'),
      (inventoryCount, 'Do physical stock counts'),
      (purchasesReturn, 'Return goods to suppliers'),
    ],
    'Cash and accounts': [
      (cashView, 'View cash register and day closing'),
      (cashShift, 'Open and close own cashier shift, cash in and out'),
      (cashCloseDay, 'Close the day and see all shifts'),
      (cashReopen, 'Reopen a closed day'),
      (accountsView, 'View account statements'),
      (accountsManage, 'Deposit, withdraw and transfer between accounts'),
      (customersDocuments, 'See and upload customer NID and documents'),
    ],
    'Expenses': [
      (expensesView, 'View expenses'),
      (expensesCreate, 'Add expenses'),
      (expensesVoid, 'Void expenses'),
    ],
    'Administration': [
      (settingsManage, 'Change business settings'),
      (usersManage, 'Manage team and roles'),
    ],
  };

  static List<String> get all => [for (final g in groups.values) for (final p in g) p.$1];
}

class Business {
  const Business({
    required this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.phone,
    this.email,
    this.website,
    this.currency = 'BDT',
    this.timezone = 'Asia/Dhaka',
    this.settings = const {},
  });

  final String id;
  final String name;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? email;
  final String? website;
  final String currency;
  final String timezone;
  final Map<String, dynamic> settings;

  factory Business.fromJson(Map<String, dynamic> j) => Business(
        id: j['id'] as String,
        name: j['name'] as String,
        logoUrl: j['logo_url'] as String?,
        address: j['address'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        website: j['website'] as String?,
        currency: (j['currency'] as String?) ?? 'BDT',
        timezone: (j['timezone'] as String?) ?? 'Asia/Dhaka',
        settings: Map<String, dynamic>.from((j['settings'] as Map?) ?? const {}),
      );

  String _s(String k, String d) => (settings[k] as String?)?.trim().isNotEmpty == true ? settings[k] as String : d;
  bool _b(String k, bool d) => settings[k] is bool ? settings[k] as bool : d;
  int _i(String k, int d) => settings[k] is num ? (settings[k] as num).toInt() : d;

  String get invoicePrefix => _s('invoice_prefix', 'INV');
  String get purchasePrefix => _s('purchase_prefix', 'PUR');
  bool get allowNegativeStock => _b('allow_negative_stock', false);
  bool get allowDueSale => _b('allow_due_sale', true);
  bool get customerRequired => _b('customer_required', false);
  bool get autoPrint => _b('auto_print', false);
  String get paperSize => _s('paper_size', '80mm');
  String get invoiceFooter => _s('invoice_footer', 'Thank you for shopping with us.');
  String get invoiceTerms => (settings['invoice_terms'] as String?) ?? '';

  /// Days after a sale during which a return needs no approval. 0 means no limit.
  int get returnWindowDays => _i('return_window_days', 0);

  /// SKU rules: prefix and number of digits for product codes made by the system.
  String get skuPrefix => _s('sku_prefix', 'P');
  int get skuDigits => _i('sku_digits', 6).clamp(3, 10).toInt();

  /// Digits that start every barcode the app generates (EAN-13, 20 to 29 is reserved for in-store use).
  String get barcodePrefix => _s('barcode_prefix', '20');

  /// Ask for the signed-in user's password before sensitive actions (void, stock adjustment, reopening a day).
  bool get requirePasswordConfirm => _b('require_password_confirm', true);
}

class AppUser {
  const AppUser({
    required this.userId,
    required this.memberId,
    required this.fullName,
    required this.role,
    required this.business,
    required this.branchId,
    required this.branchName,
    required this.permissions,
    this.email,
  });

  final String userId;
  final String memberId;
  final String fullName;
  final String role;
  final String? email;
  final Business business;
  final String branchId;
  final String branchName;
  final Set<String> permissions;

  String get businessId => business.id;
  bool get isOwner => role == 'owner';
  bool can(String permission) => isOwner || permissions.contains(permission);
  bool canAny(Iterable<String> list) => list.any(can);

  String get roleLabel => switch (role) {
        'owner' => 'Owner',
        'manager' => 'Manager',
        'cashier' => 'Cashier',
        'storekeeper' => 'Storekeeper',
        _ => role,
      };
}
