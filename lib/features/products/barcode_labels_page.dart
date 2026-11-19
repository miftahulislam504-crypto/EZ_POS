import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'products_data.dart';

/// Pick products, choose a label size and print barcode labels.
class BarcodeLabelsPage extends ConsumerStatefulWidget {
  const BarcodeLabelsPage({super.key, this.initialProductId});

  final String? initialProductId;

  @override
  ConsumerState<BarcodeLabelsPage> createState() => _BarcodeLabelsPageState();
}

class _BarcodeLabelsPageState extends ConsumerState<BarcodeLabelsPage> {
  final List<({Product product, int copies})> _items = [];
  LabelSpec _spec = LabelSpec.mm50x30;
  String _size = '50x30';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialProductId != null) _loadInitial();
  }

  Future<void> _loadInitial() async {
    final p = await ref.read(productRepoProvider).byId(widget.initialProductId!);
    if (p != null && mounted) setState(() => _items.add((product: p, copies: 1)));
  }

  Future<void> _addProduct() async {
    final picked = await showAppSheet<Product>(
      context,
      title: 'Add product',
      maxWidth: 560,
      builder: (_) => const _ProductPicker(),
    );
    if (picked != null && !_items.any((i) => i.product.id == picked.id)) {
      setState(() => _items.add((product: picked, copies: 1)));
    }
  }

  void _setSize(String v) {
    setState(() {
      _size = v;
      final base = switch (v) {
        '40x25' => LabelSpec.mm40x25,
        'a4' => LabelSpec.a4Sheet,
        _ => LabelSpec.mm50x30,
      };
      _spec = base.copyWith(showName: _spec.showName, showPrice: _spec.showPrice, showSku: _spec.showSku);
    });
  }

  Future<void> _print() async {
    if (_items.isEmpty) return;
    setState(() => _busy = true);
    try {
      await PdfBuilder.printLabels([
        for (final i in _items)
          LabelItem(
            name: i.product.name,
            code: i.product.barcode ?? i.product.sku ?? i.product.id.substring(0, 8),
            sku: i.product.sku,
            price: i.product.sellingPrice,
            copies: i.copies,
          )
      ], _spec);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormScaffold(
      title: 'Barcode labels',
      saveLabel: 'Print labels',
      saving: _busy,
      onSave: _items.isEmpty ? null : _print,
      children: [
        FormSection('Label size', children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '50x30', label: Text('50 x 30 mm')),
              ButtonSegment(value: '40x25', label: Text('40 x 25 mm')),
              ButtonSegment(value: 'a4', label: Text('A4 sheet')),
            ],
            selected: {_size},
            onSelectionChanged: (s) => _setSize(s.first),
          ),
          Wrap(spacing: 8, children: [
            FilterChip(label: const Text('Name'), selected: _spec.showName, onSelected: (v) => setState(() => _spec = _spec.copyWith(showName: v))),
            FilterChip(label: const Text('Price'), selected: _spec.showPrice, onSelected: (v) => setState(() => _spec = _spec.copyWith(showPrice: v))),
            FilterChip(label: const Text('SKU'), selected: _spec.showSku, onSelected: (v) => setState(() => _spec = _spec.copyWith(showSku: v))),
          ]),
        ]),
        FormSection('Products', children: [
          if (_items.isEmpty)
            Text('Add the products you want labels for.', style: TextStyle(color: c.textMuted)),
          for (var i = 0; i < _items.length; i++)
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_items[i].product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(_items[i].product.barcode ?? _items[i].product.sku ?? '', style: TextStyle(color: c.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: _items[i].copies > 1 ? () => setState(() => _items[i] = (product: _items[i].product, copies: _items[i].copies - 1)) : null,
                  ),
                  SizedBox(width: 28, child: Center(child: Text('${_items[i].copies}', style: const TextStyle(fontWeight: FontWeight.w800)))),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => setState(() => _items[i] = (product: _items[i].product, copies: _items[i].copies + 1)),
                  ),
                  IconButton(icon: Icon(Icons.close_rounded, color: c.danger), onPressed: () => setState(() => _items.removeAt(i))),
                ],
              ),
            ),
          AppButton('Add product', icon: Icons.add_rounded, kind: ButtonKind.secondary, onPressed: _addProduct),
        ]),
      ],
    );
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker();

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(productsProvider((search: _q, categoryId: null, limit: 30, includeInactive: false)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(hint: 'Search products', autofocus: true, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 8),
        value.when(
          data: (items) => items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No products found')))
              : Column(
                  children: [
                    for (final p in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${p.sku ?? ''}  |  ${Fmt.money(p.sellingPrice)}'),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
        ),
      ],
    );
  }
}
