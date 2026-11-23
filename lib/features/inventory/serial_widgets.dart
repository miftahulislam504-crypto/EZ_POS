import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/barcode_scanner_page.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'tracking_data.dart';

/// IMEI = 15 digits with a correct Luhn check digit (the database applies the same rule).
bool isValidImei(String s) {
  if (!RegExp(r'^[0-9]{15}$').hasMatch(s)) return false;
  var total = 0;
  for (var i = 1; i <= 15; i++) {
    var d = int.parse(s[15 - i]);
    if (i % 2 == 0) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    total += d;
  }
  return total % 10 == 0;
}

String normSerial(String s) => s.trim().toUpperCase();

/// Splits pasted or typed text (one per line, or separated by commas, semicolons or spaces).
List<String> parseSerials(String text) {
  final out = <String>[];
  for (final part in text.split(RegExp(r'[\s,;]+'))) {
    final v = normSerial(part);
    if (v.isNotEmpty) out.add(v);
  }
  return out;
}

// ---------------------------------------------------------------- typing or scanning new serial numbers

/// Used when receiving stock (purchase, increase). Returns the serial numbers, or null when cancelled.
Future<List<String>?> showSerialEntry(
  BuildContext context, {
  required String productName,
  required String kind, // imei | serial
  int? expected,
  List<String> initial = const [],
}) {
  return showAppSheet<List<String>>(
    context,
    title: kind == 'imei' ? 'Enter IMEI numbers' : 'Enter serial numbers',
    maxWidth: 520,
    builder: (_) => _SerialEntry(productName: productName, kind: kind, expected: expected, initial: initial),
  );
}

class _SerialEntry extends StatefulWidget {
  const _SerialEntry({required this.productName, required this.kind, this.expected, required this.initial});

  final String productName;
  final String kind;
  final int? expected;
  final List<String> initial;

  @override
  State<_SerialEntry> createState() => _SerialEntryState();
}

class _SerialEntryState extends State<_SerialEntry> {
  late final TextEditingController _text = TextEditingController(text: widget.initial.join('\n'));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context, title: 'Scan ${widget.kind == 'imei' ? 'IMEI' : 'serial'}');
    if (code == null) return;
    final v = normSerial(code);
    final current = parseSerials(_text.text);
    if (current.contains(v)) {
      if (mounted) showToast(context, '$v is already in the list.', error: true);
      return;
    }
    setState(() => _text.text = [...current, v].join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = parseSerials(_text.text);
    final seen = <String>{};
    final dupes = <String>{};
    for (final s in list) {
      if (!seen.add(s)) dupes.add(s);
    }
    final invalid = widget.kind == 'imei' ? [for (final s in seen) if (!isValidImei(s)) s] : <String>[];
    final countOk = widget.expected == null || seen.length == widget.expected;
    final canSave = seen.isNotEmpty && dupes.isEmpty && invalid.isEmpty && countOk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.productName, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          widget.expected == null
              ? 'One per line. You can paste a list or scan each unit.'
              : 'Enter ${widget.expected} number(s), one per line, or scan each unit.',
          style: context.text.bodySmall?.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _text,
          maxLines: 8,
          hint: widget.kind == 'imei' ? '356938035643809\n490154203237518' : 'SN-0001\nSN-0002',
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            StatusPill(
              '${seen.length}${widget.expected == null ? '' : ' of ${widget.expected}'} entered',
              tone: countOk && seen.isNotEmpty ? Tone.success : Tone.warning,
            ),
            const Spacer(),
            AppButton('Scan', icon: Icons.qr_code_scanner_rounded, kind: ButtonKind.secondary, dense: true, onPressed: _scan),
          ],
        ),
        if (dupes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Entered twice: ${dupes.join(', ')}', style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
          ),
        if (invalid.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Not a valid IMEI (15 digits with a correct check digit): ${invalid.take(4).join(', ')}${invalid.length > 4 ? '...' : ''}',
              style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 16),
        AppButton('Save ${seen.length} number(s)', expand: true, onPressed: canSave ? () => Navigator.pop(context, seen.toList()) : null),
      ],
    );
  }
}

// ---------------------------------------------------------------- choosing units that are in stock

/// Used when selling, transferring or removing stock: pick from the units that are in stock in [branchId].
Future<List<String>?> showSerialPicker(
  BuildContext context, {
  required String productId,
  required String productName,
  required String branchId,
  List<String> selected = const [],
  int? exactCount,
}) {
  return showAppSheet<List<String>>(
    context,
    title: 'Select units',
    maxWidth: 520,
    builder: (_) => _SerialPicker(productId: productId, productName: productName, branchId: branchId, selected: selected, exactCount: exactCount),
  );
}

class _SerialPicker extends ConsumerStatefulWidget {
  const _SerialPicker({required this.productId, required this.productName, required this.branchId, required this.selected, this.exactCount});

  final String productId;
  final String productName;
  final String branchId;
  final List<String> selected;
  final int? exactCount;

  @override
  ConsumerState<_SerialPicker> createState() => _SerialPickerState();
}

class _SerialPickerState extends ConsumerState<_SerialPicker> {
  late final Set<String> _picked = {...widget.selected};
  String _q = '';

  Future<void> _scan(List<StockUnit> all) async {
    final code = await scanBarcode(context, title: 'Scan unit');
    if (code == null || !mounted) return;
    final v = normSerial(code);
    if (!all.any((u) => u.serial == v)) {
      showToast(context, '$v is not in stock here.', error: true);
      return;
    }
    setState(() => _picked.add(v));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(stockUnitsProvider((productId: widget.productId, branchId: widget.branchId, status: 'in_stock', search: '', limit: 1000)));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => ErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(stockUnitsProvider)),
      data: (all) {
        final visible = _q.isEmpty ? all : all.where((u) => u.serial.contains(_q.toUpperCase())).toList();
        final need = widget.exactCount;
        final ok = _picked.isNotEmpty && (need == null || _picked.length == need);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.productName}  |  ${all.length} in stock', style: context.text.bodyMedium?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SearchField(
              hint: 'Search serial or IMEI',
              onChanged: (v) => setState(() => _q = v.trim()),
              trailing: IconButton(icon: const Icon(Icons.qr_code_scanner_rounded), onPressed: () => _scan(all)),
            ),
            const SizedBox(height: 8),
            if (all.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No units in stock.')))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final u = visible[i];
                    final on = _picked.contains(u.serial);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: on,
                      title: Text(u.serial, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                      onChanged: (v) => setState(() => v == true ? _picked.add(u.serial) : _picked.remove(u.serial)),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            AppButton(
              need == null ? 'Use ${_picked.length} unit(s)' : 'Use ${_picked.length} of $need unit(s)',
              expand: true,
              onPressed: ok ? () => Navigator.pop(context, _picked.toList()) : null,
            ),
          ],
        );
      },
    );
  }
}
