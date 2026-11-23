import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../products/product_picker.dart';
import '../products/products_data.dart';
import 'serial_widgets.dart';
import 'tracking_data.dart';
import 'transfers_data.dart';

class _TLine {
  _TLine(this.product) : qty = TextEditingController(text: '1');

  final Product product;
  final TextEditingController qty;
  List<String> serials = [];

  void dispose() => qty.dispose();
}

class TransferFormPage extends ConsumerStatefulWidget {
  const TransferFormPage({super.key});

  @override
  ConsumerState<TransferFormPage> createState() => _TransferFormPageState();
}

class _TransferFormPageState extends ConsumerState<TransferFormPage> {
  final List<_TLine> _lines = [];
  final _note = TextEditingController();
  final String _clientRef = const Uuid().v4();
  String? _from;
  String? _to;
  bool _sendNow = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    final p = await showProductPicker(context);
    if (p == null) return;
    if (_lines.any((l) => l.product.id == p.id)) {
      showToast(context, '${p.name} is already on the list.', error: true);
      return;
    }
    setState(() => _lines.add(_TLine(p)));
  }

  Future<void> _pickSerials(_TLine l) async {
    if (_from == null) {
      showToast(context, 'Choose the sending location first.', error: true);
      return;
    }
    final picked = await showSerialPicker(context, productId: l.product.id, productName: l.product.name, branchId: _from!, selected: l.serials);
    if (picked != null) {
      setState(() {
        l.serials = picked;
        l.qty.text = '${picked.length}';
      });
    }
  }

  Future<void> _save() async {
    if (_from == null || _to == null) return setState(() => _error = 'Choose where the stock is going from and to.');
    if (_from == _to) return setState(() => _error = 'Choose two different locations.');
    if (_lines.isEmpty) return setState(() => _error = 'Add at least one product.');
    for (final l in _lines) {
      final q = Fmt.parse(l.qty.text);
      if (q <= 0) return setState(() => _error = 'Enter a quantity for ${l.product.name}.');
      if (l.product.usesSerials && _sendNow && l.serials.length != q.round()) {
        return setState(() => _error = 'Select the serial/IMEI numbers of ${l.product.name}.');
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await ref.read(transfersRepoProvider).create({
        'from_branch_id': _from,
        'to_branch_id': _to,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'client_ref': _clientRef,
        'dispatch': _sendNow,
        'items': [
          for (final l in _lines)
            {'product_id': l.product.id, 'quantity': Fmt.parse(l.qty.text), if (l.product.usesSerials && l.serials.isNotEmpty) 'serials': l.serials}
        ],
      });
      refreshAfterTransaction(ref);
      if (mounted) {
        context.pushReplacement('/inventory/transfers/${res['id']}');
        showToast(context, 'Transfer ${res['transfer_no']} ${_sendNow ? 'sent' : 'requested'}');
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
    final branches = (ref.watch(branchesProvider).valueOrNull ?? const <BranchOption>[]).where((b) => b.isActive).toList();
    _from ??= ref.read(currentUserProvider).branchId;
    final opts = [for (final b in branches) PickerOption(b.id, b.name, subtitle: b.isWarehouse ? 'Warehouse' : null)];
    return FormScaffold(
      title: 'New stock transfer',
      saving: _saving,
      onSave: _save,
      saveLabel: _sendNow ? 'Send stock' : 'Save request',
      children: [
        FormSection('Locations', children: [
          if (branches.length < 2)
            Text('You need at least two locations. Add a branch or warehouse in Settings, Branches.', style: TextStyle(color: c.warning, fontWeight: FontWeight.w700)),
          FieldRow([
            PickerField<String>(label: 'From', value: _from, options: opts, onChanged: (v) => setState(() => _from = v)),
            PickerField<String>(label: 'To', value: _to, options: [for (final o in opts) if (o.value != _from) o], onChanged: (v) => setState(() => _to = v)),
          ]),
        ]),
        FormSection('Products', children: [
          for (var i = 0; i < _lines.length; i++)
            AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(_lines[i].product.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: c.danger),
                        onPressed: () {
                          final r = _lines[i];
                          setState(() => _lines.removeAt(i));
                          WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
                        },
                      ),
                    ],
                  ),
                  if (_lines[i].product.usesSerials)
                    AppButton(
                      _lines[i].serials.isEmpty ? 'Select units' : '${_lines[i].serials.length} unit(s) selected',
                      icon: Icons.qr_code_2_rounded,
                      kind: ButtonKind.secondary,
                      dense: true,
                      onPressed: () => _pickSerials(_lines[i]),
                    )
                  else
                    AppTextField(
                      controller: _lines[i].qty,
                      label: 'Quantity (in stock ${Fmt.qty(_lines[i].product.stock)})',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                    ),
                ],
              ),
            ),
          AppButton('Add product', icon: Icons.add_rounded, kind: ButtonKind.secondary, expand: true, onPressed: _add),
        ]),
        FormSection('Dispatch', children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sendNow,
            onChanged: (v) => setState(() => _sendNow = v),
            title: const Text('Send now', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Stock leaves the sending location immediately. Turn off to save a request that is sent later.'),
          ),
          AppTextField(controller: _note, label: 'Note (optional)', maxLines: 2),
          if (_error != null) Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
        ]),
      ],
    );
  }
}
