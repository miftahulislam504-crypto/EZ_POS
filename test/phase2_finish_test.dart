import 'dart:math';
import 'dart:typed_data';

import 'package:ez_pos/core/data/documents_data.dart';
import 'package:ez_pos/core/models/app_user.dart';
import 'package:ez_pos/core/printing/escpos.dart';
import 'package:ez_pos/core/printing/printer_config.dart';
import 'package:ez_pos/core/utils/barcodes.dart';
import 'package:ez_pos/features/customers/customers_data.dart';
import 'package:ez_pos/features/installments/installments_data.dart';
import 'package:ez_pos/features/sales/invoice_doc.dart';
import 'package:ez_pos/features/sales/sales_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// RGBA picture where every pixel has the same colour.
Uint8List solid(int w, int h, {required bool black, int alpha = 255}) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final v = black ? 0 : 255;
    px[i * 4] = v;
    px[i * 4 + 1] = v;
    px[i * 4 + 2] = v;
    px[i * 4 + 3] = alpha;
  }
  return px;
}

void main() {
  group('Barcode prefix rule', () {
    test('prefix is cleaned to digits and limited to six', () {
      expect(Barcodes.cleanPrefix('20'), '20');
      expect(Barcodes.cleanPrefix(' 2-5 a'), '25');
      expect(Barcodes.cleanPrefix('1234567890'), '123456');
      expect(Barcodes.cleanPrefix(''), '20');
      expect(Barcodes.cleanPrefix(null), '20');
    });

    test('generated codes are valid EAN-13 and start with the prefix', () {
      final r = Random(7);
      for (final prefix in ['20', '29', '2345', '200000']) {
        final code = Barcodes.generateEan13(prefix: prefix, random: r);
        expect(code.length, 13);
        expect(code.startsWith(prefix), isTrue);
        expect(Barcodes.isValidEan13(code), isTrue, reason: code);
      }
    });

    test('known EAN-13 check digit', () {
      expect(Barcodes.isValidEan13('4006381333931'), isTrue);
      expect(Barcodes.isValidEan13('4006381333932'), isFalse);
    });
  });

  group('ESC/POS raster encoder', () {
    test('a black row becomes one raster band of 0xFF bytes and blank rows at the end are dropped', () {
      final w = 16, h = 3;
      final px = solid(w, h, black: false);
      for (var x = 0; x < w; x++) {
        px[x * 4] = 0;
        px[x * 4 + 1] = 0;
        px[x * 4 + 2] = 0;
      }
      final out = EscPos.raster(px, w, h, outWidth: 16);
      expect(out.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 2, 0, 1, 0]);
      expect(out.sublist(8), [0xFF, 0xFF]);
    });

    test('transparent pixels print white', () {
      final out = EscPos.raster(solid(8, 2, black: true, alpha: 0), 8, 2, outWidth: 8);
      expect(out, isEmpty);
    });

    test('margins are cropped with the offset', () {
      // 24 pixels wide: black only in the first 8 columns, which the offset removes.
      final w = 24, h = 1;
      final px = solid(w, h, black: false);
      for (var x = 0; x < 8; x++) {
        px[x * 4] = 0;
        px[x * 4 + 1] = 0;
        px[x * 4 + 2] = 0;
      }
      expect(EscPos.raster(px, w, h, outWidth: 16, offsetX: 8), isEmpty);
      final kept = EscPos.raster(px, w, h, outWidth: 16, offsetX: 0);
      expect(kept.sublist(8), [0xFF, 0x00]);
    });

    test('tall pictures are sent in bands of 128 rows', () {
      final out = EscPos.raster(solid(8, 300, black: true), 8, 300, outWidth: 8);
      // 3 bands: 128 + 128 + 44 rows, each with an 8-byte header and one byte per row.
      expect(out.length, 3 * 8 + 300);
      expect(out[6], 128);
      expect(out[8 + 128 + 6], 128);
      expect(out[2 * (8 + 128) + 6], 44);
    });

    test('width is rounded up to whole bytes', () {
      final out = EscPos.raster(solid(10, 1, black: true), 10, 1, outWidth: 10);
      expect(out.sublist(0, 8), [0x1D, 0x76, 0x30, 0x00, 2, 0, 1, 0]);
      expect(out.sublist(8), [0xFF, 0xC0]);
    });

    test('a job starts with reset, and ends with feed and cut unless cutting is off', () {
      final job = EscPos.job([1, 2, 3]);
      expect(job.sublist(0, 2), [0x1B, 0x40]);
      expect(job.sublist(job.length - 4), EscPos.cut);
      final noCut = EscPos.job([1, 2, 3], cutPaper: false);
      expect(noCut.contains(0x56), isFalse);
      final drawer = EscPos.job([1], openCashDrawer: true);
      expect(drawer.sublist(2, 7), EscPos.openDrawer);
    });
  });

  group('Printer configuration', () {
    test('survives a save and load round trip', () {
      const c = PrinterConfig(link: PrinterLink.network, name: 'Counter', address: '192.168.1.50', port: 9100, cutPaper: false, openDrawer: true);
      final back = PrinterConfig.fromJson(c.toJson());
      expect(back.link, PrinterLink.network);
      expect(back.address, '192.168.1.50');
      expect(back.cutPaper, isFalse);
      expect(back.openDrawer, isTrue);
    });

    test('a printer counts as set up only when it can be reached', () {
      expect(const PrinterConfig().isConfigured, isFalse);
      expect(const PrinterConfig(link: PrinterLink.network).isConfigured, isFalse);
      expect(const PrinterConfig(link: PrinterLink.network, address: '10.0.0.5').isConfigured, isTrue);
      expect(const PrinterConfig(link: PrinterLink.bluetooth, address: '00:11:22:33:44:55').isConfigured, isTrue);
      expect(const PrinterConfig(link: PrinterLink.usb, vendorId: '1305').isConfigured, isFalse);
      expect(const PrinterConfig(link: PrinterLink.usb, vendorId: '1305', productId: '8211').isConfigured, isTrue);
    });

    test('unknown stored values fall back to the system dialog', () {
      expect(PrinterConfig.fromJson({'link': 'laser'}).link, PrinterLink.none);
    });
  });

  group('Documents', () {
    test('file names are made safe for storage paths', () {
      expect(safeFileName('NID front (1).jpg'), 'NID_front__1_.jpg');
      expect(safeFileName('../../etc/passwd'), '.._.._etc_passwd');
      expect(safeFileName(''), 'file');
      expect(safeFileName('${'a' * 200}.pdf').length, 80);
    });

    test('record parses and detects the file kind', () {
      final d = DocumentRecord.fromJson({
        'id': '1',
        'entity_type': 'customer',
        'entity_id': '2',
        'doc_type': 'nid_front',
        'storage_path': 'b/customer/2/abc-nid.JPG',
        'file_name': 'nid.JPG',
        'created_at': '2026-11-20T10:00:00Z',
      });
      expect(d.isImage, isTrue);
      expect(d.isPdf, isFalse);
      expect(documentKindLabel('customer', d.docType), 'NID front');
      expect(documentKindLabel('installment', 'agreement'), 'Signed agreement');
    });

    test('every record type offers a generic "other" kind', () {
      for (final e in kDocumentKinds.entries) {
        expect(e.value.any((k) => k.$1 == 'other'), isTrue, reason: e.key);
      }
    });
  });

  group('Business rules read from settings', () {
    Business with_(Map<String, dynamic> s) => Business(id: 'b', name: 'Shop', settings: s);

    test('defaults', () {
      final b = with_(const {});
      expect(b.returnWindowDays, 0);
      expect(b.skuPrefix, 'P');
      expect(b.skuDigits, 6);
      expect(b.barcodePrefix, '20');
      expect(b.requirePasswordConfirm, isTrue);
    });

    test('values from settings, with limits', () {
      final b = with_({'return_window_days': 7, 'sku_prefix': 'EZ', 'sku_digits': 99, 'barcode_prefix': '29', 'require_password_confirm': false});
      expect(b.returnWindowDays, 7);
      expect(b.skuPrefix, 'EZ');
      expect(b.skuDigits, 10);
      expect(b.barcodePrefix, '29');
      expect(b.requirePasswordConfirm, isFalse);
      expect(with_({'sku_digits': 1}).skuDigits, 3);
    });

    test('the return override permission exists in the permission list', () {
      expect(Perm.groups.values.any((list) => list.any((p) => p.$1 == Perm.returnsOverrideWindow)), isTrue);
    });
  });

  group('Customer installment details', () {
    test('new fields are read, and reminders default to on', () {
      final c = Customer.fromJson({
        'id': '1',
        'name': 'Nadia',
        'workplace': 'City Bank',
        'emergency_contact_name': 'Mother',
        'emergency_contact_phone': '019',
        'reminders_enabled': false,
      });
      expect(c.workplace, 'City Bank');
      expect(c.emergencyName, 'Mother');
      expect(c.emergencyPhone, '019');
      expect(c.remindersEnabled, isFalse);
      expect(Customer.fromJson({'id': '2', 'name': 'Plain'}).remindersEnabled, isTrue);
    });
  });

  group('Return receipts', () {
    ReturnReceipt receipt({double total = 800, double due = 0, double refund = 800}) => ReturnReceipt(
          returnNo: 'RET-0001',
          date: DateTime(2026, 11, 22),
          invoiceNo: 'INV-0009',
          total: total,
          dueAdjusted: due,
          refund: refund,
          lines: const [ReturnReceiptLine(name: 'Cable', qty: 10, amount: 800, condition: 'resellable')],
        );

    test('credit is what is neither taken off the due nor refunded', () {
      expect(receipt(due: 300, refund: 0).credit, 500);
      expect(receipt().credit, 0);
    });

    test('a refund prints as a refund receipt, otherwise a return receipt', () {
      expect(returnReceiptDoc(receipt()).title, 'Refund receipt');
      expect(returnReceiptDoc(receipt(due: 800, refund: 0)).title, 'Return receipt');
    });

    test('totals list only the amounts that apply', () {
      final labels = returnReceiptDoc(receipt(due: 300, refund: 0)).totals.map((t) => t.$1).toList();
      expect(labels, ['Return value', 'Taken off the invoice due', 'Kept as customer credit']);
    });
  });

  group('Installment plan after a return', () {
    test('the returned value is read from the plan', () {
      final p = InstallmentPlanRow.fromJson({
        'id': 'p',
        'plan_no': 'PLN-1',
        'sale_id': 's',
        'customer_id': 'c',
        'status': 'active',
        'product_total': 4000,
        'down_payment': 1000,
        'financed_amount': 3000,
        'service_charge': 400,
        'total_payable': 2600,
        'paid_amount': 850,
        'outstanding': 1750,
        'installment_count': 4,
        'returned_amount': 800,
        'created_at': '2026-11-20T10:00:00Z',
      });
      expect(p.returned, 800);
      expect(p.outstanding, 1750);
      expect(InstallmentPlanRow.fromJson({
        'id': 'p', 'plan_no': 'x', 'sale_id': 's', 'customer_id': 'c', 'status': 'active', 'product_total': 1, 'down_payment': 0,
        'financed_amount': 1, 'service_charge': 0, 'total_payable': 1, 'paid_amount': 0, 'outstanding': 1, 'installment_count': 1,
        'created_at': '2026-11-20T10:00:00Z',
      }).returned, 0);
    });
  });
}
