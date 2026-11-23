import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/security/password_confirm.dart';
import '../customers/customers_data.dart';
import '../customers/party_widgets.dart';
import 'invoice_doc.dart';
import '../installments/installments_data.dart';
import 'sales_data.dart';

class SaleDetailPage extends ConsumerWidget {
  const SaleDetailPage({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(saleDetailProvider(saleId));
    final c = context.colors;

    return PageScaffold(
      title: value.valueOrNull?.row.invoiceNo ?? 'Invoice',
      maxWidth: 820,
      actions: [
        if (value.hasValue) ...[
          IconButton(icon: const Icon(Icons.print_outlined), tooltip: 'Print', onPressed: () => PdfBuilder.printDoc(invoiceDoc(value.value!), user.business)),
          IconButton(icon: const Icon(Icons.ios_share_rounded), tooltip: 'Share PDF', onPressed: () => PdfBuilder.shareDoc(invoiceDoc(value.value!), user.business)),
        ],
      ],
      body: AsyncBody<SaleDetail>(
        value: value,
        onRetry: () => ref.invalidate(saleDetailProvider),
        builder: (d) {
          final r = d.row;
          final planId = ref.watch(planForSaleProvider(r.id)).valueOrNull;
          final onInstallment = planId != null;
          final windowDays = user.business.returnWindowDays;
          final pastWindow = windowDays > 0 && DateTime.now().difference(r.date).inDays > windowDays;
          final needsApproval = pastWindow && !user.can(Perm.returnsOverrideWindow);
          final canReturn = user.can(Perm.returnsCreate) && !r.isVoid && !needsApproval && d.items.any((i) => i.returnable > 0.0001);
          final canExchange = canReturn && user.can(Perm.salesCreate);
          final canVoid = user.can(Perm.salesVoid) && !r.isVoid && r.returned <= 0;
          final canCollect = user.can(Perm.customersPayment) && !r.isVoid && !onInstallment && r.due > 0.004 && r.customerId != null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.invoiceNo, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                        if (r.isVoid)
                          const StatusPill('Void')
                        else if (r.due > 0.004)
                          StatusPill(r.paid > 0 ? 'Partly paid' : 'Unpaid', tone: Tone.danger)
                        else
                          const StatusPill('Paid', tone: Tone.success),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InfoRow('Date', Fmt.dateTime(r.date)),
                    InfoRow('Customer', r.customerName ?? 'Walk-in customer'),
                    if (r.customerPhone != null) InfoRow('Phone', r.customerPhone!),
                    if (d.cashierName != null) InfoRow('Cashier', d.cashierName!),
                    if (d.note != null) InfoRow('Note', d.note!),
                    if (r.isVoid && d.voidReason != null) InfoRow('Void reason', d.voidReason!, valueColor: c.danger),
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
                                  const SizedBox(height: 2),
                                  Text(
                                    '${Fmt.qty(d.items[i].qty)}${d.items[i].unit == null ? '' : ' ${d.items[i].unit}'} x ${Fmt.money(d.items[i].price)}'
                                    '${d.items[i].discount > 0 ? '  (- ${Fmt.money(d.items[i].discount)})' : ''}',
                                    style: context.text.bodySmall?.copyWith(color: c.textMuted),
                                  ),
                                  if (d.items[i].returnedQty > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: StatusPill('${Fmt.qty(d.items[i].returnedQty)} returned', tone: Tone.warning, dense: true),
                                    ),
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
                    if (d.itemDiscount > 0) InfoRow('Item discount', '- ${Fmt.money(d.itemDiscount)}', valueColor: c.success),
                    if (d.invoiceDiscount > 0) InfoRow('Invoice discount', '- ${Fmt.money(d.invoiceDiscount)}', valueColor: c.success),
                    if (d.tax > 0) InfoRow('VAT / tax', Fmt.money(d.tax)),
                    const Divider(),
                    InfoRow('Total', Fmt.money(r.total), bold: true),
                    InfoRow('Paid', Fmt.money(r.paid)),
                    if (r.returned > 0) InfoRow('Returned', Fmt.money(r.returned), valueColor: c.warning),
                    if (r.due > 0.004) InfoRow('Due', Fmt.money(r.due), bold: true, valueColor: c.danger),
                  ],
                ),
              ),
              if (d.payments.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionHeader('Payments at sale'),
                AppCard(
                  child: Column(
                    children: [for (final p in d.payments) InfoRow(p.account + (p.reference == null ? '' : ' (${p.reference})'), Fmt.money(p.amount))],
                  ),
                ),
              ],
              if (d.returns.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionHeader('Returns'),
                for (final rt in d.returns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rt.returnNo, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text(Fmt.dateTime(rt.date), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyText(rt.total, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              if (rt.refund > 0) Text('Refunded ${Fmt.money(rt.refund)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                            ],
                          ),
                          IconButton(
                            tooltip: rt.refund > 0 ? 'Print refund receipt' : 'Print return receipt',
                            icon: const Icon(Icons.print_outlined),
                            onPressed: () async {
                              try {
                                final receipt = await ref.read(salesRepoProvider).returnReceipt(rt.id);
                                await PdfBuilder.printDoc(returnReceiptDoc(receipt), user.business);
                              } catch (e) {
                                if (context.mounted) showToast(context, friendlyError(e), error: true);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (pastWindow && !r.isVoid && user.can(Perm.returnsCreate) && d.items.any((i) => i.returnable > 0.0001)) ...[
                const SizedBox(height: 14),
                AppCard(
                  color: c.warningSoft,
                  borderColor: c.warning,
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, color: c.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          needsApproval
                              ? 'This invoice is past the $windowDays-day return period. A manager must approve the return.'
                              : 'This invoice is past the $windowDays-day return period. Your approval is recorded with the return.',
                          style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (canCollect)
                    AppButton('Receive payment', icon: Icons.payments_outlined, onPressed: () async {
                      await showPartyPaymentSheet(
                        context, ref,
                        kind: PartyKind.customer,
                        partyId: r.customerId!,
                        partyName: r.customerName ?? 'Customer',
                        partyPhone: r.customerPhone,
                        balance: r.due,
                        preselectId: r.id,
                        openItems: [OpenItem(id: r.id, number: r.invoiceNo, date: r.date, total: r.total, due: r.due, ageDays: DateTime.now().difference(r.date).inDays)],
                      );
                    }),
                  if (onInstallment && user.can(Perm.installmentsView))
                    AppButton('Installment plan', icon: Icons.event_repeat_rounded, onPressed: () => context.push('/installments/$planId')),
                  if (canExchange) AppButton('Exchange', icon: Icons.swap_horiz_rounded, kind: ButtonKind.secondary, onPressed: () => context.push('/sales/${r.id}/exchange')),
                  if (canReturn) AppButton('Return items', icon: Icons.assignment_return_outlined, kind: ButtonKind.secondary, onPressed: () => context.push('/sales/${r.id}/return')),
                  if (canVoid)
                    AppButton('Void sale', icon: Icons.block_rounded, kind: ButtonKind.danger, onPressed: () async {
                      final reason = await reasonDialog(context, title: 'Void ${r.invoiceNo}?', message: 'Stock will be restored and payments reversed. This cannot be undone.', confirmLabel: 'Void sale');
                      if (reason == null || !context.mounted) return;
                      if (!await confirmSensitive(context, ref)) return;
                      try {
                        await ref.read(salesRepoProvider).voidSale(r.id, reason);
                        refreshAfterTransaction(ref);
                        if (context.mounted) showToast(context, 'Sale voided');
                      } catch (e) {
                        if (context.mounted) showToast(context, friendlyError(e), error: true);
                      }
                    }),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
