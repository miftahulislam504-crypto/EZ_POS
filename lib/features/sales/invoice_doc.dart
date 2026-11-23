import '../../core/printing/pdf_builder.dart';
import '../../core/utils/format.dart';
import 'sales_data.dart';

PrintableDoc invoiceDoc(SaleDetail d) {
  final r = d.row;
  return PrintableDoc(
    title: 'Invoice',
    number: r.invoiceNo,
    date: r.date,
    partyLabel: 'Customer',
    partyName: r.customerName,
    partyPhone: r.customerPhone,
    partyAddress: d.customerAddress,
    meta: [if (d.cashierName != null) ('Cashier', d.cashierName!)],
    status: r.isVoid ? 'VOID' : null,
    lines: [
      for (final i in d.items)
        PrintLine(
          name: i.name,
          qty: '${Fmt.qty(i.qty)}${i.unit == null ? '' : ' ${i.unit}'}',
          price: i.price,
          discount: i.discount,
          total: i.qty * i.price - i.discount,
        ),
    ],
    totals: [
      ('Items total', Fmt.pdfMoney(d.subtotal), false),
      if (d.itemDiscount > 0) ('Item discount', '-${Fmt.pdfMoney(d.itemDiscount)}', false),
      if (d.invoiceDiscount > 0) ('Invoice discount', '-${Fmt.pdfMoney(d.invoiceDiscount)}', false),
      if (d.tax > 0) ('VAT / tax', Fmt.pdfMoney(d.tax), false),
      ('Total', Fmt.pdfMoney(r.total), true),
      ('Paid', Fmt.pdfMoney(r.paid), false),
      if (r.returned > 0) ('Returned', Fmt.pdfMoney(r.returned), false),
      if (r.due > 0.004) ('Due', Fmt.pdfMoney(r.due), true),
    ],
    payments: [for (final p in d.payments) (p.account, Fmt.pdfMoney(p.amount))],
    note: d.note,
    qrData: r.invoiceNo,
  );
}

/// Refund receipt (money went back) or return receipt (credit or due reduced only).
PrintableDoc returnReceiptDoc(ReturnReceipt r) {
  return PrintableDoc(
    title: r.refund > 0.004 ? 'Refund receipt' : 'Return receipt',
    number: r.returnNo,
    date: r.date,
    partyLabel: 'Customer',
    partyName: r.customerName,
    partyPhone: r.customerPhone,
    meta: [
      ('Invoice', r.invoiceNo),
      if (r.refundAccount != null && r.refund > 0.004) ('Refund via', r.refundAccount!),
    ],
    lines: [
      for (final i in r.lines)
        PrintLine(
          name: i.name,
          qty: Fmt.qty(i.qty),
          price: i.qty <= 0 ? i.amount : i.amount / i.qty,
          total: i.amount,
          sub: i.condition == 'resellable' ? null : (i.condition == 'damaged' ? 'Damaged' : 'Needs inspection'),
        ),
    ],
    totals: [
      ('Return value', Fmt.pdfMoney(r.total), true),
      if (r.dueAdjusted > 0.004) ('Taken off the invoice due', Fmt.pdfMoney(r.dueAdjusted), false),
      if (r.refund > 0.004) ('Refunded', Fmt.pdfMoney(r.refund), true),
      if (r.credit > 0.004) ('Kept as customer credit', Fmt.pdfMoney(r.credit), false),
    ],
    note: r.reason,
    qrData: r.returnNo,
  );
}
