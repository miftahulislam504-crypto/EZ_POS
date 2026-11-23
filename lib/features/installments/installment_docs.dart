import '../../core/printing/pdf_builder.dart';
import '../../core/utils/format.dart';
import 'installments_data.dart';

/// Agreement and payment schedule for the customer.
PrintableDoc installmentAgreementDoc(PlanDetail d) {
  final p = d.plan;
  final guarantors = [
    for (final g in d.guarantors)
      '${g.kind == 'guarantor' ? 'Guarantor' : g.kind == 'reference' ? 'Reference' : 'Emergency contact'}: ${g.name}'
          '${g.relationship == null ? '' : ' (${g.relationship})'}${g.phone == null ? '' : ', ${g.phone}'}',
  ];
  return PrintableDoc(
    title: 'Installment agreement',
    number: p.planNo,
    date: p.createdAt,
    partyName: p.customerName,
    partyPhone: p.customerPhone,
    meta: [('Invoice', p.invoiceNo), ('Schedule', '${p.count} x ${kFrequencyLabels[p.frequency] ?? p.frequency}')],
    simple: true,
    lines: [
      for (final i in d.items)
        PrintLine(
          name: 'Installment ${i.seq}  |  due ${Fmt.date(i.dueDate)}${i.status == 'paid' ? '  |  paid' : ''}',
          qty: '1',
          price: i.amount,
          total: i.amount,
        ),
    ],
    totals: [
      ('Product total', Fmt.pdfMoney(p.productTotal), false),
      ('Down payment', Fmt.pdfMoney(p.downPayment), false),
      ('Financed amount', Fmt.pdfMoney(p.financed), false),
      if (p.serviceCharge > 0) ('Service charge', Fmt.pdfMoney(p.serviceCharge), false),
      ('Total payable', Fmt.pdfMoney(p.totalPayable), true),
      ('Paid so far', Fmt.pdfMoney(p.paid), false),
      ('Outstanding', Fmt.pdfMoney(p.outstanding), true),
    ],
    note: [
      if ((p.terms ?? '').isNotEmpty) p.terms!,
      ...guarantors,
      'Customer signature: ____________________',
    ].join('\n'),
    qrData: p.planNo,
  );
}

PrintableDoc installmentReceiptDoc(PlanDetail d, InstallmentPayment pay) {
  final p = d.plan;
  return PrintableDoc(
    title: 'Installment receipt',
    number: pay.receiptNo,
    date: pay.date,
    partyName: p.customerName,
    partyPhone: p.customerPhone,
    meta: [('Plan', p.planNo), ('Invoice', p.invoiceNo)],
    simple: true,
    lines: [PrintLine(name: 'Installment payment', qty: '1', price: pay.amount, total: pay.amount)],
    totals: [
      ('Received', Fmt.pdfMoney(pay.amount), true),
      if (pay.advance > 0.004) ('Kept as advance', Fmt.pdfMoney(pay.advance), false),
      ('Outstanding on plan', Fmt.pdfMoney(p.outstanding), false),
    ],
    payments: [(pay.accountName, Fmt.pdfMoney(pay.amount))],
    note: pay.reference == null ? null : 'Reference: ${pay.reference}',
    qrData: pay.receiptNo,
  );
}
