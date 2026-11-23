import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../customers/party_widgets.dart';
import '../inventory/serial_widgets.dart';
import '../products/products_tab.dart';
import 'checkout_sheet.dart';
import 'customer_picker.dart';
import 'pos_controller.dart';

class CartPanel extends ConsumerWidget {
  const CartPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cart = ref.watch(cartProvider);
    final user = ref.watch(currentUserProvider);
    final totals = cart.totals;
    final notifier = ref.read(cartProvider.notifier);

    Future<void> pickCustomer() async {
      final pick = await showCustomerPicker(context);
      if (pick != null) notifier.setCustomer(pick.customer);
    }

    return Container(
      color: c.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text('Current sale', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                if (!cart.isEmpty) ...[
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(heldCartsProvider.notifier).hold(cart);
                      notifier.clear();
                      if (context.mounted) showToast(context, 'Sale put on hold');
                    },
                    icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
                    label: const Text('Hold'),
                  ),
                  IconButton(
                    tooltip: 'Clear cart',
                    icon: Icon(Icons.delete_sweep_outlined, color: c.danger),
                    onPressed: () async {
                      if (await confirmDialog(context, title: 'Clear this sale?', message: 'All items will be removed from the cart.', confirmLabel: 'Clear', danger: true)) {
                        notifier.clear();
                      }
                    },
                  ),
                ],
                if (onClose != null) IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: pickCustomer,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Avatar(cart.customer?.name ?? 'Walk-in', size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cart.customer?.name ?? 'Walk-in customer', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (cart.customer?.phone != null) Text(cart.customer!.phone!, style: TextStyle(color: c.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (cart.customer != null && cart.customer!.balance.abs() > 0.004) BalanceLabel(cart.customer!.balance),
                    const SizedBox(width: 6),
                    Icon(Icons.expand_more_rounded, color: c.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: cart.isEmpty
                ? const EmptyState(icon: Icons.shopping_basket_outlined, title: 'Cart is empty', message: 'Tap a product or scan a barcode to add it.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => Divider(color: c.border, height: 20),
                    itemBuilder: (_, i) => _LineTile(line: cart.lines[i], lineNetC: totals.lineNetC[i], canDiscount: user.can(Perm.salesDiscount)),
                  ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InfoRow('Subtotal (${Fmt.qty(cart.quantity)} items)', Fmt.money(totals.gross), padding: const EdgeInsets.symmetric(vertical: 3)),
                  if (totals.itemDiscountC > 0)
                    InfoRow('Item discounts', '- ${Fmt.money(totals.itemDiscount)}', valueColor: c.success, padding: const EdgeInsets.symmetric(vertical: 3)),
                  if (user.can(Perm.salesDiscount) && !cart.isEmpty)
                    InkWell(
                      onTap: () => _editInvoiceDiscount(context, ref, cart.invoiceDiscount, totals),
                      child: InfoRow(
                        'Invoice discount',
                        totals.invoiceDiscountC > 0 ? '- ${Fmt.money(totals.invoiceDiscount)}' : 'Add',
                        valueColor: totals.invoiceDiscountC > 0 ? c.success : c.primary,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                      ),
                    ),
                  if (totals.taxC > 0) InfoRow('VAT / tax', Fmt.money(totals.tax), padding: const EdgeInsets.symmetric(vertical: 3)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Total', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: totals.total),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => Text(Fmt.money(v), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Add note',
                        onPressed: cart.isEmpty ? null : () => _editNote(context, ref, cart.note),
                        icon: Icon(cart.note.isEmpty ? Icons.sticky_note_2_outlined : Icons.sticky_note_2_rounded),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          cart.isEmpty ? 'Charge' : 'Charge ${Fmt.money(totals.total)}',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: cart.isEmpty ? null : () => showCheckout(context, ref),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editInvoiceDiscount(BuildContext context, WidgetRef ref, double current, CartTotals totals) async {
    final controller = TextEditingController(text: current > 0 ? current.toStringAsFixed(2) : '');
    final value = await showAppSheet<double>(
      context,
      title: 'Invoice discount',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MoneyField(controller: controller, label: 'Discount amount', autofocus: true),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final p in const [5, 10, 15])
              ActionChip(
                label: Text('$p%'),
                onPressed: () => controller.text = (Cents.toDouble(totals.netC + totals.invoiceDiscountC) * p / 100).toStringAsFixed(2),
              ),
          ]),
          const SizedBox(height: 18),
          AppButton('Apply discount', expand: true, onPressed: () => Navigator.pop(ctx, Fmt.parse(controller.text))),
        ],
      ),
    );
    if (value != null) ref.read(cartProvider.notifier).setInvoiceDiscount(value);
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final value = await showAppSheet<String>(
      context,
      title: 'Sale note',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(controller: controller, label: 'Note', hint: 'Printed on the invoice', maxLines: 3, autofocus: true),
          const SizedBox(height: 18),
          AppButton('Save note', expand: true, onPressed: () => Navigator.pop(ctx, controller.text)),
        ],
      ),
    );
    if (value != null) ref.read(cartProvider.notifier).setNote(value);
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.line, required this.lineNetC, required this.canDiscount});

  final CartLine line;
  final int lineNetC;
  final bool canDiscount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final n = ref.read(cartProvider.notifier);
    final p = line.product;

    void tryQty(double q) {
      final err = n.setQty(p.id, q);
      if (err != null) showToast(context, err, error: true);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _editLine(context, ref, line, canDiscount),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductThumb(url: p.imageUrl, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.money(line.price)}${p.unitName == null ? '' : ' / ${p.unitName}'}${line.discount > 0 ? '   - ${Fmt.money(line.discount)}' : ''}',
                  style: context.text.bodySmall?.copyWith(color: line.discount > 0 ? c.success : c.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (p.usesSerials)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final picked = await showSerialPicker(
                        context,
                        productId: p.id,
                        productName: p.name,
                        branchId: ref.read(currentUserProvider).branchId,
                        selected: line.serials,
                      );
                      if (picked != null) n.setSerials(p, picked);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_2_rounded, size: 16, color: c.primary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${line.serials.length} unit(s): ${line.serials.take(2).join(', ')}${line.serials.length > 2 ? '...' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(color: c.primary, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                Row(
                  children: [
                    _StepButton(icon: Icons.remove_rounded, onTap: () => tryQty(line.qty - 1)),
                    GestureDetector(
                      onTap: () => _editLine(context, ref, line, canDiscount),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 44),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(Fmt.qty(line.qty), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    _StepButton(icon: Icons.add_rounded, onTap: () => tryQty(line.qty + 1)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(Cents.toDouble(lineNetC), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: c.textMuted),
                onPressed: () => n.remove(p.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: SizedBox(width: 34, height: 34, child: Icon(icon, size: 18))),
    );
  }
}

Future<void> _editLine(BuildContext context, WidgetRef ref, CartLine line, bool canDiscount) async {
  final qty = TextEditingController(text: Fmt.qty(line.qty));
  final price = TextEditingController(text: line.price.toStringAsFixed(2));
  final discount = TextEditingController(text: line.discount > 0 ? line.discount.toStringAsFixed(2) : '');
  await showAppSheet<void>(
    context,
    title: line.product.name,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!line.product.usesSerials) ...[
          AppTextField(
            controller: qty,
            label: 'Quantity${line.product.unitName == null ? '' : ' (${line.product.unitName})'}',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
          const SizedBox(height: 14),
        ],
        MoneyField(controller: price, label: 'Unit price', enabled: canDiscount),
        const SizedBox(height: 14),
        MoneyField(controller: discount, label: 'Line discount (amount)', enabled: canDiscount),
        if (!canDiscount)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('You do not have permission to change prices or give discounts.', style: ctx.text.bodySmall?.copyWith(color: ctx.colors.textMuted)),
          ),
        const SizedBox(height: 20),
        AppButton('Update item', expand: true, onPressed: () {
          final n = ref.read(cartProvider.notifier);
          if (!line.product.usesSerials) {
            final err = n.setQty(line.product.id, Fmt.parse(qty.text));
            if (err != null) {
              showToast(ctx, err, error: true);
              return;
            }
          }
          if (canDiscount) n.updateLine(line.product.id, price: Fmt.parse(price.text), discount: Fmt.parse(discount.text));
          Navigator.pop(ctx);
        }),
      ],
    ),
  );
}
