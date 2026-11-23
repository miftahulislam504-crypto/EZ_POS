import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../products/product_picker.dart';
import 'transfers_data.dart';

/// Past and open stock counts, with a button to start a new one.
class StockCountsPage extends ConsumerWidget {
  const StockCountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(stockCountsProvider);
    return PageScaffold(
      title: 'Stock counts',
      subtitle: 'Compare the shelf with the system and fix the difference',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/inventory/counts/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New count'),
      ),
      body: AsyncBody<List<StockCountRow>>(
        value: value,
        onRetry: () => ref.invalidate(stockCountsProvider),
        builder: (rows) => rows.isEmpty
            ? const EmptyState(icon: Icons.fact_check_outlined, title: 'No stock counts yet', message: 'Start a count, enter what is on the shelf, then finish to correct the stock.')
            : AdaptiveList(
                rowHeight: 76,
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return AppCard(
                    onTap: () => context.push('/inventory/counts/${r.id}'),
                    child: Row(
                      children: [
                        IconBadge(Icons.fact_check_outlined, tone: r.isDraft ? Tone.warning : Tone.success, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.countNo, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              Text(Fmt.dateTime(r.createdAt), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                            ],
                          ),
                        ),
                        StatusPill(r.isDraft ? 'In progress' : 'Completed', tone: r.isDraft ? Tone.warning : Tone.success),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CountLine {
  _CountLine({required this.productId, required this.productName, required double counted, this.system = 0, String? reason})
      : counted = TextEditingController(text: Fmt.qty(counted)),
        reason = TextEditingController(text: reason ?? '');

  final String productId;
  final String productName;
  final double system;
  final TextEditingController counted;
  final TextEditingController reason;

  void dispose() {
    counted.dispose();
    reason.dispose();
  }
}

/// Enter or review a count. Pass [countId] to continue a saved count.
class StockCountPage extends ConsumerStatefulWidget {
  const StockCountPage({super.key, this.countId});

  final String? countId;

  @override
  ConsumerState<StockCountPage> createState() => _StockCountPageState();
}

class _StockCountPageState extends ConsumerState<StockCountPage> {
  final List<_CountLine> _lines = [];
  String? _id;
  bool _completed = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _id = widget.countId;
    if (_id == null) _loaded = true;
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    final p = await showProductPicker(context, title: 'Count a product');
    if (p == null) return;
    if (p.trackingType != 'none') {
      if (mounted) showToast(context, '${p.name} is counted by serial or batch, not here.', error: true);
      return;
    }
    if (_lines.any((l) => l.productId == p.id)) return;
    setState(() => _lines.add(_CountLine(productId: p.id, productName: p.name, counted: p.stock, system: p.stock)));
  }

  Future<void> _save({required bool finalize}) async {
    if (_lines.isEmpty) return setState(() => _error = 'Add at least one product.');
    for (final l in _lines) {
      final diff = Fmt.parse(l.counted.text) - l.system;
      if (finalize && diff.abs() > 0.0005 && l.reason.text.trim().isEmpty) {
        return setState(() => _error = 'Write the reason for the difference on ${l.productName}.');
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await ref.read(transfersRepoProvider).saveCount({
        if (_id != null) 'id': _id,
        'finalize': finalize,
        'items': [
          for (final l in _lines)
            {'product_id': l.productId, 'counted_quantity': Fmt.parse(l.counted.text), 'reason': l.reason.text.trim().isEmpty ? null : l.reason.text.trim()}
        ],
      });
      refreshAfterTransaction(ref);
      ref.invalidate(stockCountsProvider);
      if (mounted) {
        context.pop();
        showToast(context, finalize ? 'Count finished. Stock corrected for ${res['adjusted_products']} product(s).' : 'Count saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canAdjust = ref.watch(currentUserProvider).can(Perm.inventoryAdjust);
    if (_id != null && !_loaded) {
      final d = ref.watch(stockCountDetailProvider(_id!));
      return PageScaffold(
        title: 'Stock count',
        body: AsyncBody<StockCountRow>(
          value: d,
          onRetry: () => ref.invalidate(stockCountDetailProvider(_id!)),
          builder: (row) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _loaded) return;
              setState(() {
                _loaded = true;
                _completed = !row.isDraft;
                for (final i in row.items) {
                  _lines.add(_CountLine(productId: i.productId, productName: i.name, counted: i.counted, system: i.system, reason: i.reason));
                }
              });
            });
            return const SizedBox.shrink();
          },
        ),
      );
    }
    return FormScaffold(
      title: _completed ? 'Stock count (completed)' : 'Stock count',
      saving: _saving,
      onSave: () => _completed ? context.pop() : _save(finalize: canAdjust),
      saveLabel: canAdjust && !_completed ? 'Finish and correct stock' : 'Done',
      secondary: _completed
          ? null
          : AppButton('Save draft', kind: ButtonKind.secondary, onPressed: _saving ? null : () => _save(finalize: false)),
      children: [
        FormSection('Counted products', subtitle: 'Enter what is on the shelf. The difference is corrected when you finish.', children: [
          for (var i = 0; i < _lines.length; i++)
            AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_lines[i].productName, style: const TextStyle(fontWeight: FontWeight.w800))),
                      if (!_completed)
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: c.danger),
                          onPressed: () {
                            final l = _lines[i];
                            setState(() => _lines.removeAt(i));
                            WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose());
                          },
                        ),
                    ],
                  ),
                  Text('System ${Fmt.qty(_lines[i].system)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                  const SizedBox(height: 8),
                  FieldRow([
                    AppTextField(
                      controller: _lines[i].counted,
                      label: 'Counted',
                      readOnly: _completed,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                      onChanged: (_) => setState(() {}),
                    ),
                    AppTextField(controller: _lines[i].reason, label: 'Reason for difference', readOnly: _completed),
                  ]),
                  Builder(builder: (_) {
                    final diff = Fmt.parse(_lines[i].counted.text) - _lines[i].system;
                    if (diff.abs() < 0.0005) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${diff > 0 ? 'Surplus' : 'Shortage'} ${Fmt.qty(diff.abs())}', style: TextStyle(color: diff > 0 ? c.success : c.danger, fontWeight: FontWeight.w800)),
                    );
                  }),
                ],
              ),
            ),
          if (!_completed) AppButton('Add product', icon: Icons.add_rounded, kind: ButtonKind.secondary, expand: true, onPressed: _add),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
        ]),
      ],
    );
  }
}
