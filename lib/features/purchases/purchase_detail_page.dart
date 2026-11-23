import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/attachments_section.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../customers/customers_data.dart';
import '../customers/party_widgets.dart';
import 'purchases_data.dart';

PrintableDoc purchaseDoc(PurchaseDetail d) {
  final r = d.row;
  return PrintableDoc(
    title: 'Purchase bill',
    number: r.purchaseNo,
    date: r.date,
    partyLabel: 'Supplier',
    partyName: r.supplierName,
    partyPhone: d.supplierPhone,
    partyAddress: d.supplierAddress,
    meta: [if (r.supplierInvoiceNo != null) ('Supplier invoice', r.supplierInvoiceNo!)],
    lines: [for (final i in d.items) PrintLine(name: i.name, qty: Fmt.qty(i.qty), price: i.unitCost, discount: i.discount, total: i.total)],
    totals: [
      ('Items total', Fmt.pdfMoney(d.subtotal), false),
      if (d.discount > 0) ('Discount', '-${Fmt.pdfMoney(d.discount)}', false),
      if (d.tax > 0) ('VAT / tax', Fmt.pdfMoney(d.tax), false),
      if (d.otherCharges > 0) ('Other charges', Fmt.pdfMoney(d.otherCharges), false),
      ('Total', Fmt.pdfMoney(r.total), true),
      ('Paid', Fmt.pdfMoney(r.paid), false),
      if (r.due > 0.004) ('Due', Fmt.pdfMoney(r.due), true),
    ],
    payments: [for (final p in d.payments) (p.account, Fmt.pdfMoney(p.amount))],
    note: d.note,
    qrData: r.purchaseNo,
  );
}

class PurchaseDetailPage extends ConsumerWidget {
  const PurchaseDetailPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(purchaseDetailProvider(purchaseId));
    final c = context.colors;
    return PageScaffold(
      title: value.valueOrNull?.row.purchaseNo ?? 'Purchase',
      maxWidth: 820,
      actions: [
        if (value.hasValue) ...[
          IconButton(icon: const Icon(Icons.print_outlined), onPressed: () => PdfBuilder.printDoc(purchaseDoc(value.value!), user.business, paper: PaperSize.a4)),
          IconButton(icon: const Icon(Icons.ios_share_rounded), onPressed: () => PdfBuilder.shareDoc(purchaseDoc(value.value!), user.business, paper: PaperSize.a4)),
        ],
      ],
      body: AsyncBody<PurchaseDetail>(
        value: value,
        onRetry: () => ref.invalidate(purchaseDetailProvider),
        builder: (d) {
          final r = d.row;
          final returns = ref.watch(purchaseReturnsProvider(purchaseId)).valueOrNull ?? const <Map<String, dynamic>>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              AppCard(
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(child: Text(r.purchaseNo, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      r.due > 0.004 ? StatusPill(r.paid > 0 ? 'Partly paid' : 'Unpaid', tone: Tone.danger) : const StatusPill('Paid', tone: Tone.success),
                    ]),
                    const SizedBox(height: 8),
                    InfoRow('Supplier', r.supplierName ?? '-'),
                    InfoRow('Date', Fmt.date(r.date)),
                    if (r.supplierInvoiceNo != null) InfoRow('Supplier invoice', r.supplierInvoiceNo!),
                    if (d.note != null) InfoRow('Note', d.note!),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionHeader('Items'),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < d.items.length; i++) ...[
                      if (i > 0) Divider(color: c.border),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.items[i].name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                  Text('${Fmt.qty(d.items[i].qty)} x ${Fmt.money(d.items[i].unitCost)}${d.items[i].discount > 0 ? '  (- ${Fmt.money(d.items[i].discount)})' : ''}',
                                      style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                  if (user.can(Perm.reportsView))
                                    Text('Landed cost ${Fmt.money(d.items[i].landed)} each', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                ],
                              ),
                            ),
                            MoneyText(d.items[i].total, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  children: [
                    InfoRow('Items total', Fmt.money(d.subtotal)),
                    if (d.discount > 0) InfoRow('Discount', '- ${Fmt.money(d.discount)}', valueColor: c.success),
                    if (d.tax > 0) InfoRow('VAT / tax', Fmt.money(d.tax)),
                    if (d.otherCharges > 0) InfoRow('Other charges', Fmt.money(d.otherCharges)),
                    const Divider(),
                    InfoRow('Total', Fmt.money(r.total), bold: true),
                    InfoRow('Paid', Fmt.money(r.paid)),
                    if (r.due > 0.004) InfoRow('Due', Fmt.money(r.due), bold: true, valueColor: c.danger),
                  ],
                ),
              ),
              if (d.payments.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionHeader('Payments at purchase'),
                AppCard(child: Column(children: [for (final p in d.payments) InfoRow(p.account, Fmt.money(p.amount))])),
              ],
              if (returns.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionHeader('Returns to supplier'),
                AppCard(
                  child: Column(
                    children: [
                      for (final x in returns)
                        InfoRow(
                          '${x['return_no']}  |  ${Fmt.date(parseDate(x['return_date']))}',
                          Fmt.money(dbl(x['total'])),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AttachmentsSection(
                entityType: 'purchase',
                entityId: r.id,
                title: 'Bills and attachments',
                subtitle: 'Supplier challan, bill or payment slip',
                canEdit: user.can(Perm.purchasesCreate),
                canDelete: user.can(Perm.purchasesCreate),
              ),
              if (user.can(Perm.purchasesReturn)) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton('Return to supplier', icon: Icons.undo_rounded, kind: ButtonKind.secondary, onPressed: () => context.push('/purchases/$purchaseId/return')),
                ),
              ],
              if (r.due > 0.004 && r.supplierId != null && user.can(Perm.suppliersPayment)) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton('Pay supplier', icon: Icons.payments_outlined, onPressed: () async {
                    await showPartyPaymentSheet(
                      context, ref,
                      kind: PartyKind.supplier,
                      partyId: r.supplierId!,
                      partyName: r.supplierName ?? 'Supplier',
                      partyPhone: d.supplierPhone,
                      balance: r.due,
                      preselectId: r.id,
                      openItems: [OpenItem(id: r.id, number: r.purchaseNo, date: r.date, total: r.total, due: r.due, ageDays: DateTime.now().difference(r.date).inDays)],
                    );
                  }),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
