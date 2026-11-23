import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/security/password_confirm.dart';
import 'serial_widgets.dart';
import 'transfers_data.dart';
import 'transfers_page.dart';

class TransferDetailPage extends ConsumerWidget {
  const TransferDetailPage({super.key, required this.transferId});

  final String transferId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(transferDetailProvider(transferId));
    return PageScaffold(
      title: 'Stock transfer',
      maxWidth: 780,
      body: AsyncBody<TransferDetail>(
        value: value,
        onRetry: () => ref.invalidate(transferDetailProvider(transferId)),
        builder: (d) => _Body(detail: d),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final TransferDetail detail;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      refreshAfterTransaction(ref);
      ref.invalidate(transferDetailProvider(detail.row.id));
      if (context.mounted) showToast(context, done);
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _dispatch(BuildContext context, WidgetRef ref) async {
    final items = <Map<String, dynamic>>[];
    for (final it in detail.items) {
      if (it.usesSerials && it.serials.length != it.quantity.round()) {
        final picked = await showSerialPicker(
          context,
          productId: it.productId,
          productName: it.name,
          branchId: detail.row.fromId,
          selected: it.serials,
          exactCount: it.quantity.round(),
        );
        if (picked == null) return;
        items.add({'item_id': it.id, 'serials': picked});
      }
    }
    if (!context.mounted) return;
    await _run(context, ref, () => ref.read(transfersRepoProvider).dispatch({'id': detail.row.id, if (items.isNotEmpty) 'items': items}), 'Stock sent');
  }

  Future<void> _receive(BuildContext context, WidgetRef ref) async {
    final payload = await showAppSheet<Map<String, dynamic>>(context, title: 'Receive stock', maxWidth: 560, builder: (_) => _ReceiveForm(detail: detail));
    if (payload == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(transfersRepoProvider).receive({'id': detail.row.id, ...payload}), 'Stock received');
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await reasonDialog(context, title: 'Cancel transfer', message: 'Stock already sent is returned to the sending location.', confirmLabel: 'Cancel transfer');
    if (reason == null || !context.mounted) return;
    if (!await confirmSensitive(context, ref)) return;
    if (!context.mounted) return;
    await _run(context, ref, () => ref.read(transfersRepoProvider).cancel(detail.row.id, reason), 'Transfer cancelled');
  }

  PrintableDoc _doc() => PrintableDoc(
        title: 'Stock transfer note',
        number: detail.row.transferNo,
        date: detail.row.dispatchedAt ?? detail.row.requestedAt,
        partyLabel: 'To',
        partyName: detail.row.toName,
        meta: [('From', detail.row.fromName), ('Status', detail.row.statusLabel)],
        simple: true,
        amountLabel: 'Quantity',
        lines: [
          for (final i in detail.items)
            PrintLine(
              name: '${i.name}${i.serials.isEmpty ? '' : '\n${i.serials.join(', ')}'}',
              qty: Fmt.qty(i.quantity),
              price: 0,
              total: i.sent == 0 ? i.quantity : i.sent,
            )
        ],
        totals: const [],
        note: detail.row.note,
        qrData: detail.row.transferNo,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final r = detail.row;
    final manage = user.can(Perm.transfersManage);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: [
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: Text(r.transferNo, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  StatusPill(r.statusLabel, tone: transferTone(r.status)),
                ],
              ),
              const SizedBox(height: 12),
              InfoRow('From', r.fromName),
              InfoRow('To', r.toName),
              InfoRow('Requested', Fmt.dateTime(r.requestedAt)),
              if (r.dispatchedAt != null) InfoRow('Sent', Fmt.dateTime(r.dispatchedAt!)),
              if (r.receivedAt != null) InfoRow('Completed', Fmt.dateTime(r.receivedAt!)),
              if ((r.note ?? '').isNotEmpty) InfoRow('Note', r.note!),
              if ((r.cancelReason ?? '').isNotEmpty) InfoRow('Cancelled because', r.cancelReason!, valueColor: c.danger),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (manage && r.status == 'requested') AppButton('Send stock', icon: Icons.local_shipping_outlined, dense: true, onPressed: () => _dispatch(context, ref)),
            if (manage && (r.status == 'in_transit' || r.status == 'partially_received'))
              AppButton('Receive', icon: Icons.inventory_2_outlined, dense: true, onPressed: () => _receive(context, ref)),
            if (manage && (r.status == 'requested' || r.status == 'in_transit'))
              AppButton('Cancel', icon: Icons.close_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => _cancel(context, ref)),
            AppButton('Print note', icon: Icons.print_outlined, kind: ButtonKind.secondary, dense: true, onPressed: () async {
              try {
                await PdfBuilder.printDoc(_doc(), user.business, paper: PaperSize.a4);
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            }),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader('Items'),
        for (final i in detail.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text('${Fmt.qty(i.received)} / ${Fmt.qty(i.sent == 0 ? i.quantity : i.sent)}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  if (i.serials.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(i.serials.map((s) => i.receivedSerials.contains(s) ? '$s (received)' : s).join('\n'), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                    ),
                  if ((i.shortageReason ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Missing ${Fmt.qty(i.sent - i.received)}: ${i.shortageReason}', style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReceiveForm extends StatefulWidget {
  const _ReceiveForm({required this.detail});

  final TransferDetail detail;

  @override
  State<_ReceiveForm> createState() => _ReceiveFormState();
}

class _ReceiveFormState extends State<_ReceiveForm> {
  late final Map<String, TextEditingController> _qty = {
    for (final i in widget.detail.items.where((i) => i.onTheWay > 0 && !i.usesSerials)) i.id: TextEditingController(text: Fmt.qty(i.onTheWay)),
  };
  late final Map<String, Set<String>> _serials = {
    for (final i in widget.detail.items.where((i) => i.onTheWay > 0 && i.usesSerials)) i.id: {...i.pendingSerials},
  };
  final _reason = TextEditingController();
  bool _short = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final items = <Map<String, dynamic>>[];
    for (final i in widget.detail.items.where((i) => i.onTheWay > 0)) {
      if (i.usesSerials) {
        final s = _serials[i.id]!;
        items.add({'item_id': i.id, 'quantity': s.length, 'serials': s.toList()});
      } else {
        final q = Fmt.parse(_qty[i.id]!.text);
        if (q > i.onTheWay + 0.0005) return setState(() => _error = 'Only ${Fmt.qty(i.onTheWay)} of ${i.name} is on the way.');
        items.add({'item_id': i.id, 'quantity': q});
      }
    }
    final receivedAny = items.any((x) => (x['quantity'] as num) > 0);
    if (!receivedAny && !_short) return setState(() => _error = 'Enter what was received.');
    if (_short && _reason.text.trim().isEmpty) return setState(() => _error = 'Write the reason for the missing quantity.');
    Navigator.pop(context, {'items': items, if (_short) 'close_short': true, if (_short) 'short_reason': _reason.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in widget.detail.items.where((i) => i.onTheWay > 0)) ...[
          Text('${i.name}  |  ${Fmt.qty(i.onTheWay)} on the way', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (i.usesSerials)
            for (final s in i.pendingSerials)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _serials[i.id]!.contains(s),
                title: Text(s),
                onChanged: (v) => setState(() => v == true ? _serials[i.id]!.add(s) : _serials[i.id]!.remove(s)),
              )
          else
            AppTextField(
              controller: _qty[i.id]!,
              label: 'Received',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
            ),
          const SizedBox(height: 14),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _short,
          onChanged: (v) => setState(() => _short = v),
          title: const Text('Close with missing quantity', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Anything not received is written off and the difference is recorded'),
        ),
        if (_short) AppTextField(controller: _reason, label: 'Reason for the difference', maxLines: 2),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 14),
        AppButton('Confirm receipt', expand: true, onPressed: _submit),
      ],
    );
  }
}
