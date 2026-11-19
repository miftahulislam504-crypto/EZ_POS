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
