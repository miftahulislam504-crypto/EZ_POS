import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/barcode_scanner_page.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../inventory/adjust_stock_sheet.dart';
import 'products_data.dart';

class ProductsTab extends ConsumerStatefulWidget {
  const ProductsTab({super.key});

  @override
  ConsumerState<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<ProductsTab> {
  final _search = TextEditingController();
  String _q = '';
  String? _categoryId;
  int _limit = AppConfig.listPageSize;
  bool _showInactive = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ProductQuery get _query => (search: _q, categoryId: _categoryId, limit: _limit, includeInactive: _showInactive);

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null) return;
    _search.text = code;
    setState(() {
      _q = code;
      _limit = AppConfig.listPageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final products = ref.watch(productsProvider(_query));
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: user.can(Perm.productsManage)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/products/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add product'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SearchField(
                    controller: _search,
                    hint: 'Search name, SKU or barcode',
                    onChanged: (v) => setState(() {
                      _q = v;
                      _limit = AppConfig.listPageSize;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded), tooltip: 'Scan'),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) {
                    if (v == 'inactive') setState(() => _showInactive = !_showInactive);
                    if (v == 'catalog') context.push('/settings/catalog');
                    if (v == 'labels') context.push('/products/labels');
                  },
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(value: 'inactive', checked: _showInactive, child: const Text('Show inactive')),
                    const PopupMenuItem(value: 'catalog', child: Text('Categories, brands and units')),
                    const PopupMenuItem(value: 'labels', child: Text('Print barcode labels')),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _categoryId == null,
                    onSelected: (_) => setState(() => _categoryId = null),
                  ),
                ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() => _categoryId = _categoryId == c.id ? null : c.id),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Product>>(
              value: products,
              onRetry: () => ref.invalidate(productsProvider),
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: _q.isEmpty ? 'No products yet' : 'No products found',
                    message: _q.isEmpty ? 'Add your first product to start selling.' : 'Try a different name, SKU or barcode.',
                    actionLabel: _q.isEmpty && user.can(Perm.productsManage) ? 'Add product' : null,
                    onAction: () => context.push('/products/new'),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(productsProvider),
                  child: AdaptiveList(
                    itemCount: items.length,
                    rowHeight: 84,
                    footer: items.length >= _limit
                        ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize))
                        : null,
                    itemBuilder: (_, i) => ProductTile(product: items[i], onTap: () => showProductSheet(context, ref, items[i])),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, this.url, this.size = 52});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(size * 0.26)),
      child: url != null && url!.isNotEmpty
          ? Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported_outlined, color: c.textMuted, size: size * 0.4))
          : Icon(Icons.inventory_2_outlined, color: c.textMuted, size: size * 0.42),
    );
  }
}

class StockPill extends StatelessWidget {
  const StockPill({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    if (product.isService) return const StatusPill('Service', dense: true);
    final tone = product.outOfStock ? Tone.danger : (product.lowStock ? Tone.warning : Tone.success);
    final label = product.outOfStock ? 'Out of stock' : '${Fmt.qty(product.stock)} ${product.unitName ?? ''}'.trim();
    return StatusPill(label, tone: tone, dense: true);
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = [
      if (product.sku != null) product.sku!,
      if (product.categoryName != null) product.categoryName!,
      if (!product.isActive) 'Inactive',
    ].join('  |  ');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ProductThumb(url: product.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(product.sellingPrice, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              StockPill(product: product),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showProductSheet(BuildContext context, WidgetRef ref, Product p) {
  final user = ref.read(currentUserProvider);
  return showAppSheet<void>(
    context,
    title: p.name,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProductThumb(url: p.imageUrl, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MoneyText(p.sellingPrice, style: ctx.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    StockPill(product: p),
                    if (!p.isActive) const StatusPill('Inactive', dense: true),
                    if (p.taxRate > 0) StatusPill('VAT ${Fmt.pct(p.taxRate)}', tone: Tone.info, dense: true),
                  ]),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        InfoRow('SKU', p.sku ?? '-'),
        InfoRow('Barcode', p.barcode ?? '-'),
        InfoRow('Category', p.categoryName ?? '-'),
        InfoRow('Brand', p.brandName ?? '-'),
        if (p.model != null) InfoRow('Model', p.model!),
        if (user.can(Perm.reportsView)) ...[
          InfoRow('Purchase price', Fmt.money(p.purchasePrice)),
          InfoRow('Average cost', Fmt.money(p.avgCost)),
        ],
        if (p.wholesalePrice != null) InfoRow('Wholesale price', Fmt.money(p.wholesalePrice)),
        if (p.minSellingPrice != null) InfoRow('Minimum selling price', Fmt.money(p.minSellingPrice)),
        if (p.warrantyMonths != null) InfoRow('Warranty', '${p.warrantyMonths} months'),
        if (p.trackStock) ...[
          InfoRow('In stock', '${Fmt.qty(p.stock)} ${p.unitName ?? ''}'),
          if (p.damaged > 0) InfoRow('Damaged', Fmt.qty(p.damaged)),
          InfoRow('Low stock alert at', p.lowStockLimit > 0 ? Fmt.qty(p.lowStockLimit) : 'Off'),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (user.can(Perm.productsManage))
              AppButton('Edit', icon: Icons.edit_outlined, dense: true, onPressed: () {
                Navigator.pop(ctx);
                context.push('/products/${p.id}/edit');
              }),
            if (user.can(Perm.inventoryAdjust) && p.trackStock)
              AppButton('Adjust stock', icon: Icons.tune_rounded, dense: true, kind: ButtonKind.secondary, onPressed: () {
                Navigator.pop(ctx);
                showAdjustStockSheet(context, ref, productId: p.id, productName: p.name, unit: p.unitName);
              }),
            AppButton('Print label', icon: Icons.label_outline_rounded, dense: true, kind: ButtonKind.secondary, onPressed: () {
              Navigator.pop(ctx);
              context.push('/products/labels?product=${p.id}');
            }),
            if (user.can(Perm.productsManage))
              AppButton(p.isActive ? 'Deactivate' : 'Activate', dense: true, kind: ButtonKind.text, onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(productRepoProvider).setActive(p.id, !p.isActive);
                  ref.invalidate(productsProvider);
                  ref.invalidate(productByIdProvider);
                  if (context.mounted) showToast(context, p.isActive ? 'Product deactivated' : 'Product activated');
                } catch (e) {
                  if (context.mounted) showToast(context, friendlyError(e), error: true);
                }
              }),
          ],
        ),
      ],
    ),
  );
}
