import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/providers.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../customers/customers_data.dart';
import '../products/products_data.dart';

class CartLine {
  const CartLine({required this.product, required this.qty, required this.price, this.discount = 0});

  final Product product;
  final double qty;
  final double price;
  final double discount;

  CartLine copyWith({double? qty, double? price, double? discount}) =>
      CartLine(product: product, qty: qty ?? this.qty, price: price ?? this.price, discount: discount ?? this.discount);

  // Everything below is integer cents and matches create_sale() in the database exactly.
  int get grossC => ((qty * 1000).round() * Cents.of(price) + 500) ~/ 1000;
  int get discountC => Cents.of(discount).clamp(0, grossC).toInt();
  int get net1C => grossC - discountC;

  Map<String, dynamic> toJson() => {'product': product.toCache(), 'qty': qty, 'price': price, 'discount': discount};

  factory CartLine.fromJson(Map<String, dynamic> j) => CartLine(
        product: Product.fromCache(asMap(j['product'])),
        qty: dbl(j['qty']),
        price: dbl(j['price']),
        discount: dbl(j['discount']),
      );
}

class CartTotals {
  const CartTotals({
    required this.grossC,
    required this.itemDiscountC,
    required this.invoiceDiscountC,
    required this.netC,
    required this.taxC,
    required this.lineNetC,
    required this.lineTaxC,
  });

  final int grossC;
  final int itemDiscountC;
  final int invoiceDiscountC;
  final int netC;
  final int taxC;
  final List<int> lineNetC;
  final List<int> lineTaxC;

  int get totalC => netC + taxC;
  double get gross => Cents.toDouble(grossC);
  double get itemDiscount => Cents.toDouble(itemDiscountC);
  double get invoiceDiscount => Cents.toDouble(invoiceDiscountC);
  double get tax => Cents.toDouble(taxC);
  double get total => Cents.toDouble(totalC);
}

class CartState {
  const CartState({this.lines = const [], this.invoiceDiscount = 0, this.customer, this.note = ''});

  final List<CartLine> lines;
  final double invoiceDiscount;
  final Customer? customer;
  final String note;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.length;
  double get quantity => lines.fold(0, (s, l) => s + l.qty);

  CartState copyWith({List<CartLine>? lines, double? invoiceDiscount, Customer? customer, bool clearCustomer = false, String? note}) =>
      CartState(
        lines: lines ?? this.lines,
        invoiceDiscount: invoiceDiscount ?? this.invoiceDiscount,
        customer: clearCustomer ? null : (customer ?? this.customer),
        note: note ?? this.note,
      );

  CartTotals get totals {
    final sub1 = lines.fold<int>(0, (s, l) => s + l.net1C);
    final int invD = Cents.of(invoiceDiscount).clamp(0, sub1).toInt();
    var gross = 0, itemDisc = 0, net = 0, tax = 0;
    final lineNet = <int>[];
    final lineTax = <int>[];
    for (final l in lines) {
      gross += l.grossC;
      itemDisc += l.discountC;
      final n = sub1 > 0 ? (l.net1C * (sub1 - invD) * 2 + sub1) ~/ (2 * sub1) : 0;
      final rateBp = (l.product.taxRate * 100).round();
      final t = (n * rateBp + 5000) ~/ 10000;
      lineNet.add(n);
      lineTax.add(t);
      net += n;
      tax += t;
    }
    return CartTotals(
      grossC: gross,
      itemDiscountC: itemDisc,
      invoiceDiscountC: invD,
      netC: net,
      taxC: tax,
      lineNetC: lineNet,
      lineTaxC: lineTax,
    );
  }

  Map<String, dynamic> toPayload({required List<Map<String, dynamic>> payments, required String clientRef}) => {
        'customer_id': customer?.id,
        'note': note.trim().isEmpty ? null : note.trim(),
        'invoice_discount': invoiceDiscount,
        'client_ref': clientRef,
        'items': [
          for (final l in lines)
            {'product_id': l.product.id, 'quantity': l.qty, 'unit_price': l.price, 'discount': l.discount}
        ],
        'payments': payments,
      };
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    ref.watch(userIdProvider); // a new user always starts with an empty cart
    return const CartState();
  }

  double _priceFor(Product p) {
    final wholesale = state.customer?.group == 'wholesale' && p.wholesalePrice != null;
    return wholesale ? p.wholesalePrice! : p.sellingPrice;
  }

  /// Adds one unit (or [qty]). Returns a message when the item cannot be added, otherwise null.
  String? add(Product p, {double qty = 1}) {
    final allowNegative = ref.read(appUserProvider).valueOrNull?.business.allowNegativeStock ?? false;
    final idx = state.lines.indexWhere((l) => l.product.id == p.id);
    final current = idx >= 0 ? state.lines[idx].qty : 0.0;
    if (p.trackStock && !allowNegative && current + qty > p.stock + 0.0001) {
      return p.stock <= 0 ? '"${p.name}" is out of stock.' : 'Only ${Fmt.qty(p.stock)} of "${p.name}" in stock.';
    }
    final lines = [...state.lines];
    if (idx >= 0) {
      lines[idx] = lines[idx].copyWith(qty: current + qty);
    } else {
      lines.add(CartLine(product: p, qty: qty, price: _priceFor(p)));
    }
    state = state.copyWith(lines: lines);
    return null;
  }

  String? setQty(String productId, double qty) {
    final idx = state.lines.indexWhere((l) => l.product.id == productId);
    if (idx < 0) return null;
    if (qty <= 0) {
      remove(productId);
      return null;
    }
    final line = state.lines[idx];
    final allowNegative = ref.read(appUserProvider).valueOrNull?.business.allowNegativeStock ?? false;
    if (line.product.trackStock && !allowNegative && qty > line.product.stock + 0.0001) {
      return 'Only ${Fmt.qty(line.product.stock)} of "${line.product.name}" in stock.';
    }
    final lines = [...state.lines];
    lines[idx] = line.copyWith(qty: qty);
    state = state.copyWith(lines: lines);
    return null;
  }

  void updateLine(String productId, {double? price, double? discount}) {
    final lines = [
      for (final l in state.lines) l.product.id == productId ? l.copyWith(price: price, discount: discount) : l,
    ];
    state = state.copyWith(lines: lines);
  }

  void remove(String productId) => state = state.copyWith(lines: [for (final l in state.lines) if (l.product.id != productId) l]);

  void setInvoiceDiscount(double v) => state = state.copyWith(invoiceDiscount: v < 0 ? 0 : v);

  void setCustomer(Customer? c) {
    if (c == null) {
      state = state.copyWith(clearCustomer: true);
      return;
    }
    // Re-price lines for wholesale customers when a wholesale price exists.
    final lines = [
      for (final l in state.lines)
        c.group == 'wholesale' && l.product.wholesalePrice != null && l.price == l.product.sellingPrice
            ? l.copyWith(price: l.product.wholesalePrice)
            : l,
    ];
    state = state.copyWith(customer: c, lines: lines);
  }

  void setNote(String v) => state = state.copyWith(note: v);

  void clear() => state = const CartState();

  void restore(CartState s) => state = s;
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

// ---------------------------------------------------------------- held carts
class HeldCart {
  const HeldCart({required this.id, required this.name, required this.createdAt, required this.cart});

  final String id;
  final String name;
  final DateTime createdAt;
  final CartState cart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'lines': [for (final l in cart.lines) l.toJson()],
        'invoice_discount': cart.invoiceDiscount,
        'customer': cart.customer?.toCache(),
        'note': cart.note,
      };

  factory HeldCart.fromJson(Map<String, dynamic> j) => HeldCart(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        cart: CartState(
          lines: [for (final l in asRows(j['lines'])) CartLine.fromJson(l)],
          invoiceDiscount: dbl(j['invoice_discount']),
          customer: j['customer'] == null ? null : Customer.fromCache(asMap(j['customer'])),
          note: (j['note'] as String?) ?? '',
        ),
      );
}

class HeldCartsNotifier extends Notifier<List<HeldCart>> {
  static const _key = 'held_carts';

  @override
  List<HeldCart> build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final j in (jsonDecode(raw) as List)) HeldCart.fromJson(asMap(j))];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save() => ref.read(sharedPrefsProvider).setString(_key, jsonEncode([for (final h in state) h.toJson()]));

  Future<void> hold(CartState cart, {String? name}) async {
    final label = (name == null || name.trim().isEmpty) ? 'Cart ${state.length + 1}' : name.trim();
    state = [...state, HeldCart(id: const Uuid().v4(), name: label, createdAt: DateTime.now(), cart: cart)];
    await _save();
  }

  Future<void> discard(String id) async {
    state = [for (final h in state) if (h.id != id) h];
    await _save();
  }
}

final heldCartsProvider = NotifierProvider<HeldCartsNotifier, List<HeldCart>>(HeldCartsNotifier.new);
