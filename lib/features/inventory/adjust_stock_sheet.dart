import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../dashboard/dashboard_data.dart';
import '../products/products_data.dart';
import 'inventory_data.dart';

Future<void> showAdjustStockSheet(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  required String productName,
  String? unit,
}) {
  return showAppSheet<void>(
    context,
    title: 'Adjust stock',
    builder: (_) => _AdjustForm(productId: productId, productName: productName, unit: unit),
  );
}

class _AdjustForm extends ConsumerStatefulWidget {
  const _AdjustForm({required this.productId, required this.productName, this.unit});

  final String productId;
  final String productName;
  final String? unit;

  @override
  ConsumerState<_AdjustForm> createState() => _AdjustFormState();
}

class _AdjustFormState extends ConsumerState<_AdjustForm> {
  static const _kinds = <(String, String, IconData)>[
    ('increase', 'Add stock', Icons.add_circle_outline_rounded),
    ('decrease', 'Remove stock', Icons.remove_circle_outline_rounded),
    ('opening', 'Opening stock', Icons.flag_outlined),
    ('damage', 'Damaged', Icons.broken_image_outlined),
    ('loss', 'Lost', Icons.search_off_rounded),
    ('expired', 'Expired', Icons.event_busy_outlined),
  ];

  String _kind = 'increase';
  final _qty = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _qtyError;
  String? _noteError;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = Fmt.parse(_qty.text);
    setState(() {
      _qtyError = qty <= 0 ? 'Enter a quantity greater than zero' : null;
      _noteError = _kind != 'opening' && _note.text.trim().isEmpty ? 'A reason is required' : null;
    });
    if (_qtyError != null || _noteError != null) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventoryRepoProvider).adjust(
            productId: widget.productId,
            kind: _kind,
            quantity: qty,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.invalidate(stockReportProvider);
      ref.invalidate(stockMovementsProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(dashboardSummaryProvider);
      if (mounted) {
        Navigator.pop(context);
        showToast(context, 'Stock updated');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.productName, style: context.text.titleSmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in _kinds)
              ChoiceChip(
                avatar: Icon(k.$3, size: 18),
                label: Text(k.$2),
                selected: _kind == k.$1,
                onSelected: (_) => setState(() => _kind = k.$1),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AppTextField(
          controller: _qty,
          label: 'Quantity${widget.unit == null ? '' : ' (${widget.unit})'}',
          hint: '0',
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (_qtyError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_qtyError!, style: TextStyle(color: c.danger, fontSize: 12))),
        const SizedBox(height: 14),
        AppTextField(
          controller: _note,
          label: _kind == 'opening' ? 'Note (optional)' : 'Reason',
          hint: _kind == 'opening' ? 'Opening count' : 'Why is the stock changing?',
          maxLines: 2,
        ),
        if (_noteError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_noteError!, style: TextStyle(color: c.danger, fontSize: 12))),
        const SizedBox(height: 22),
        AppButton('Save adjustment', onPressed: _submit, loading: _saving, expand: true),
      ],
    );
  }
}
