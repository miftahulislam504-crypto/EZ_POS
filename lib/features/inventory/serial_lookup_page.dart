import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/barcode_scanner_page.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'tracking_data.dart';

/// Look up any serial or IMEI: current state, who bought it, warranty and its whole history.
class SerialLookupPage extends ConsumerStatefulWidget {
  const SerialLookupPage({super.key, this.initial});

  final String? initial;

  @override
  ConsumerState<SerialLookupPage> createState() => _SerialLookupPageState();
}

class _SerialLookupPageState extends ConsumerState<SerialLookupPage> {
  late final _ctl = TextEditingController(text: widget.initial);
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = (widget.initial ?? '').trim();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _go(String v) => setState(() => _query = v.trim().toUpperCase());

  Future<void> _scan() async {
    final code = await scanBarcode(context, title: 'Scan serial or IMEI');
    if (code != null) {
      _ctl.text = code;
      _go(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PageScaffold(
      title: 'Serial and IMEI lookup',
      maxWidth: 720,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          Row(
            children: [
              Expanded(child: AppTextField(controller: _ctl, label: 'Serial or IMEI number', onSubmitted: _go, textInputAction: TextInputAction.search)),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 0), child: IconButton.filledTonal(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded))),
              const SizedBox(width: 4),
              IconButton.filled(onPressed: () => _go(_ctl.text), icon: const Icon(Icons.search_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          if (_query.isEmpty)
            const EmptyState(icon: Icons.manage_search_rounded, title: 'Find a unit', message: 'Enter or scan a number to see its status, buyer, warranty and history.')
          else
            ref.watch(serialLookupProvider(_query)).when(
                  loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => ErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(serialLookupProvider(_query))),
                  data: (info) {
                    if (info == null) return const EmptyState(icon: Icons.search_off_rounded, title: 'Not found', message: 'No unit with this number exists in your records.');
                    final warranty = info.warrantyUntil;
                    final tone = switch (info.status) {
                      'in_stock' => Tone.success,
                      'sold' => Tone.info,
                      'in_transit' => Tone.warning,
                      _ => Tone.danger,
                    };
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppCard(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(info.serial, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                                  StatusPill(unitStatusLabels[info.status] ?? info.status, tone: tone),
                                ],
                              ),
                              const SizedBox(height: 10),
                              InfoRow('Product', info.productName),
                              InfoRow('Type', info.kind == 'imei' ? 'IMEI' : 'Serial number'),
                              if (info.branchName != null) InfoRow('Location', info.branchName!),
                              if (info.purchaseNo != null) InfoRow('Bought on', info.purchaseNo!),
                              if (info.invoiceNo != null) InfoRow('Sold on', '${info.invoiceNo}  |  ${Fmt.dateTime(info.soldAt)}'),
                              if (info.customerName != null) InfoRow('Customer', '${info.customerName}${info.customerPhone == null ? '' : '  |  ${info.customerPhone}'}'),
                              if (warranty != null)
                                InfoRow('Warranty until', Fmt.date(warranty), valueColor: warranty.isBefore(DateTime.now()) ? c.danger : c.success, bold: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SectionHeader('History'),
                        for (final e in info.events.reversed)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history_rounded),
                            title: Text(e.type.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${Fmt.dateTime(e.at)}${e.note == null || e.note!.isEmpty ? '' : '  |  ${e.note}'}'),
                            trailing: e.to == null ? null : Text(unitStatusLabels[e.to] ?? e.to!, style: TextStyle(color: c.textMuted, fontSize: 12)),
                          ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }
}

/// Batches that are expired or close to expiry, earliest first.
class ExpiryPage extends ConsumerStatefulWidget {
  const ExpiryPage({super.key});

  @override
  ConsumerState<ExpiryPage> createState() => _ExpiryPageState();
}

class _ExpiryPageState extends ConsumerState<ExpiryPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = ref.watch(expiryProvider(_days));
    return PageScaffold(
      title: 'Expiry alerts',
      maxWidth: 760,
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final d in const [7, 15, 30, 60, 90])
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text('Next $d days'), selected: _days == d, onSelected: (_) => setState(() => _days = d))),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<ExpiryRow>>(
              value: value,
              onRetry: () => ref.invalidate(expiryProvider),
              builder: (rows) {
                if (rows.isEmpty) return const EmptyState(icon: Icons.event_available_rounded, title: 'Nothing is expiring', message: 'No batch expires in this period.');
                final total = rows.fold<double>(0, (s, r) => s + r.value);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                  children: [
                    Text('${rows.length} batches  |  stock value ${Fmt.money(total)}', style: context.text.labelLarge?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          child: Row(
                            children: [
                              IconBadge(r.expired ? Icons.warning_amber_rounded : Icons.hourglass_bottom_rounded, tone: r.expired ? Tone.danger : Tone.warning, size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.productName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Text('Batch ${r.batchNo}  |  ${Fmt.qty(r.quantity)} left${r.branchName == null ? '' : '  |  ${r.branchName}'}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(Fmt.date(r.expiry), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(r.expired ? 'Expired ${-r.daysLeft}d ago' : '${r.daysLeft} day(s) left', style: TextStyle(color: r.expired ? c.danger : c.warning, fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
