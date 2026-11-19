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

  String get invoicePrefix => _s('invoice_prefix', 'INV');
  String get purchasePrefix => _s('purchase_prefix', 'PUR');
  bool get allowNegativeStock => _b('allow_negative_stock', false);
  bool get allowDueSale => _b('allow_due_sale', true);
  bool get customerRequired => _b('customer_required', false);
  bool get autoPrint => _b('auto_print', false);
  String get paperSize => _s('paper_size', '80mm');
  String get invoiceFooter => _s('invoice_footer', 'Thank you for shopping with us.');
  String get invoiceTerms => (settings['invoice_terms'] as String?) ?? '';
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
