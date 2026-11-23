import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import 'products_data.dart';
import 'products_tab.dart';

/// Search and pick one stock-tracked product.
Future<Product?> showProductPicker(BuildContext context, {String title = 'Add product'}) {
  return showAppSheet<Product>(context, title: title, maxWidth: 560, builder: (_) => const _ProductPickerBody());
}

class _ProductPickerBody extends ConsumerStatefulWidget {
  const _ProductPickerBody();

  @override
  ConsumerState<_ProductPickerBody> createState() => _ProductPickerBodyState();
}

class _ProductPickerBodyState extends ConsumerState<_ProductPickerBody> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(productsProvider((search: _q, categoryId: null, limit: 40, includeInactive: false)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(hint: 'Search products', autofocus: true, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 8),
        value.when(
          data: (items) {
            final list = items.where((p) => p.trackStock).toList();
            return list.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No products found')))
                : Column(
                    children: [
                      for (final p in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ProductThumb(url: p.imageUrl, size: 42),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${p.sku ?? ''}  |  In stock ${Fmt.qty(p.stock)}${p.trackingType == 'none' ? '' : '  |  ${p.trackingType.toUpperCase()}'}'),
                          onTap: () => Navigator.pop(context, p),
                        ),
                    ],
                  );
          },
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(friendlyError(e))),
        ),
      ],
    );
  }
}
