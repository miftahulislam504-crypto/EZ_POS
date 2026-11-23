import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/security/password_confirm.dart';
import '../dashboard/dashboard_data.dart';
import '../products/products_data.dart';
import 'inventory_data.dart';
import 'serial_widgets.dart';
import 'tracking_data.dart';

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
  final _batch = TextEditingController();
  DateTime? _expiry;
  List<String> _serials = const [];
  bool _saving = false;
  String? _qtyError;
  String? _noteError;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    _batch.dispose();
    super.dispose();
  }

  bool get _adding => _kind == 'increase' || _kind == 'opening';

  Future<void> _chooseSerials(String tracking) async {
    final picked = _adding
        ? await showSerialEntry(context, productName: widget.productName, kind: tracking, initial: _serials)
        : await showSerialPicker(
            context,
            productId: widget.productId,
            productName: widget.productName,
            branchId: ref.read(currentUserProvider).branchId,
            selected: _serials,
          );
    if (picked != null) setState(() => _serials = picked);
  }

  Future<void> _submit(String tracking) async {
    final tracked = tracking == 'serial' || tracking == 'imei';
    final qty = tracked ? _serials.length.toDouble() : Fmt.parse(_qty.text);
    setState(() {
      _qtyError = qty <= 0 ? (tracked ? 'Choose the serial numbers' : 'Enter a quantity greater than zero') : null;
      _noteError = _kind != 'opening' && _note.text.trim().isEmpty ? 'A reason is required' : null;
    });
    if (_qtyError != null || _noteError != null) return;
    if (_adding && tracking == 'batch' && _batch.text.trim().isEmpty) {
      showToast(context, 'Enter the batch number.', error: true);
      return;
    }
    if (_adding && tracking == 'expiry' && _expiry == null) {
      showToast(context, 'Choose the expiry date.', error: true);
      return;
    }
    if (_kind != 'opening') {
      if (!await confirmSensitive(context, ref, message: 'Stock adjustments change your stock value. Enter your password to continue.')) return;
      if (!mounted) return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(inventoryRepoProvider).adjust(
            productId: widget.productId,
            kind: _kind,
            quantity: qty,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            serials: tracked ? _serials : null,
            batchNo: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
            expiry: _adding ? _expiry : null,
          );
      ref.invalidate(stockReportProvider);
      ref.invalidate(stockMovementsProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(stockUnitsProvider);
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
    final tracking = ref.watch(productTrackingProvider(widget.productId)).valueOrNull ?? 'none';
    final tracked = tracking == 'serial' || tracking == 'imei';
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
        if (tracked)
          AppButton(
            _serials.isEmpty ? (_adding ? 'Enter ${tracking == 'imei' ? 'IMEI' : 'serial'} numbers' : 'Select units') : '${_serials.length} unit(s) selected',
            icon: Icons.qr_code_2_rounded,
            kind: ButtonKind.secondary,
            expand: true,
            onPressed: () => _chooseSerials(tracking),
          )
        else
          AppTextField(
            controller: _qty,
            label: 'Quantity${widget.unit == null ? '' : ' (${widget.unit})'}',
            hint: '0',
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        if (tracking == 'batch' || tracking == 'expiry') ...[
          const SizedBox(height: 14),
          FieldRow([
            AppTextField(controller: _batch, label: _adding ? 'Batch number' : 'Batch number (optional)', hint: _adding ? '' : 'Blank = earliest expiry first'),
            if (_adding)
              DateField(label: tracking == 'expiry' ? 'Expiry date' : 'Expiry date (optional)', value: _expiry, allowClear: true, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365 * 10)), onChanged: (d) => setState(() => _expiry = d)),
          ]),
        ],
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
        AppButton('Save adjustment', onPressed: () => _submit(tracking), loading: _saving, expand: true),
      ],
    );
  }
}
