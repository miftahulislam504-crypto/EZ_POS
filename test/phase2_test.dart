import 'package:ez_pos/features/installments/installment_setup_sheet.dart';
import 'package:ez_pos/features/installments/installments_data.dart';
import 'package:ez_pos/features/inventory/serial_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IMEI and serial helpers', () {
    test('IMEI check digit follows the Luhn rule used by the database', () {
      expect(isValidImei('356938035643809'), isTrue);
      expect(isValidImei('356938035643808'), isFalse);
      expect(isValidImei('12345'), isFalse);
      expect(isValidImei('35693803564380A'), isFalse);
    });

    test('pasted serial lists are split and upper-cased', () {
      expect(parseSerials('sn-1\nSN-2, sn-3;  sn-4'), ['SN-1', 'SN-2', 'SN-3', 'SN-4']);
      expect(parseSerials('  \n '), isEmpty);
    });
  });

  group('Installment plan maths', () {
    final first = DateTime(2026, 12, 1);

    test('percent service charge is applied to the financed amount', () {
      final s = InstallmentSetup(count: 4, frequency: 'monthly', firstDue: first, serviceCharge: 10, chargeMode: 'percent');
      expect(s.chargeFor(12000), 1200);
      expect(s.totalPayable(12000), 13200);
    });

    test('flat service charge is used as typed', () {
      final s = InstallmentSetup(count: 3, frequency: 'weekly', firstDue: first, serviceCharge: 250.5);
      expect(s.chargeFor(9000), 250.5);
      expect(s.totalPayable(9000), 9250.5);
    });

    test('payload matches what create_installment_sale expects', () {
      final s = InstallmentSetup(
        count: 6,
        frequency: 'monthly',
        firstDue: first,
        serviceCharge: 5,
        chargeMode: 'percent',
        terms: ' Pay on time ',
        guarantors: const [Guarantor(name: 'Salma', phone: '0171')],
      );
      final p = s.toPayload();
      expect(p['count'], 6);
      expect(p['frequency'], 'monthly');
      expect(p['first_due_date'], '2026-12-01');
      expect(p['service_charge_mode'], 'percent');
      expect(p['terms'], 'Pay on time');
      expect((p['guarantors'] as List).length, 1);
      expect(p.containsKey('custom_schedule'), isFalse);
    });

    test('custom schedule sends dates and amounts', () {
      final s = InstallmentSetup(
        count: 2,
        frequency: 'custom',
        firstDue: first,
        custom: [(date: DateTime(2026, 12, 5), amount: 500), (date: DateTime(2027, 1, 5), amount: 700)],
      );
      final p = s.toPayload();
      expect(p['count'], 2);
      expect((p['custom_schedule'] as List).first, {'due_date': '2026-12-05', 'amount': 500.0});
    });
  });

  group('Installment items', () {
    test('overdue means unpaid and past the due date', () {
      final today = DateTime(2026, 11, 21);
      InstallmentItem item(String status, DateTime due) =>
          InstallmentItem(id: 'x', seq: 1, dueDate: due, originalDueDate: due, amount: 100, paid: status == 'paid' ? 100 : 0, status: status);
      expect(item('pending', DateTime(2026, 11, 20)).isOverdueOn(today), isTrue);
      expect(item('pending', DateTime(2026, 11, 21)).isOverdueOn(today), isFalse);
      expect(item('paid', DateTime(2026, 11, 1)).isOverdueOn(today), isFalse);
      expect(item('partial', DateTime(2026, 11, 1)).remaining, 100);
    });
  });
}
