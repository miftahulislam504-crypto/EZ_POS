import 'package:ez_pos/core/utils/format.dart';
import 'package:ez_pos/features/pos/pos_controller.dart';
import 'package:ez_pos/features/products/products_data.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(String id, double price, {double tax = 0}) => Product(id: id, name: id, sellingPrice: price, taxRate: tax, stock: 100);

void main() {
  group('Cart maths matches the database', () {
    test('line discount, invoice discount and tax are computed in integer cents', () {
      // Same numbers as supabase/tests/scenario_phase1.py (sale 1): total 533.09
      final cart = CartState(
        lines: [
          CartLine(product: _p('a', 150), qty: 2, price: 150, discount: 10),
          CartLine(product: _p('b', 80, tax: 10), qty: 3, price: 80),
        ],
        invoiceDiscount: 20,
      );
      final t = cart.totals;
      expect(t.totalC, 53309);
      expect(t.itemDiscountC, 1000);
      expect(t.invoiceDiscountC, 2000);
      expect(t.taxC, 2309);
    });

    test('empty cart totals are zero', () {
      expect(const CartState().totals.totalC, 0);
    });

    test('discount cannot exceed the line value', () {
      final cart = CartState(lines: [CartLine(product: _p('a', 10), qty: 1, price: 10, discount: 50)]);
      expect(cart.totals.totalC, 0);
    });
  });

  group('Formatting', () {
    test('money uses South Asian grouping', () {
      expect(Fmt.money(1234567.5, symbol: false), '12,34,567.50');
    });

    test('quantity trims trailing zeros', () {
      expect(Fmt.qty(2), '2');
      expect(Fmt.qty(2.5), '2.5');
      expect(Fmt.qty(0.125), '0.125');
    });
  });
}
