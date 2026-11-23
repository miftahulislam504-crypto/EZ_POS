import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/barcode_scanner_page.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../inventory/serial_widgets.dart';
import '../products/products_data.dart';
import '../products/products_tab.dart';
import 'cart_panel.dart';
import 'checkout_sheet.dart';
import 'customer_picker.dart';
import 'pos_controller.dart';

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _q = '';
  String? _categoryId;

  /// Keyboard and barcode-scanner use: the search box is ready as soon as the counter screen opens.
  bool get _hasKeyboard =>
      kIsWeb || const {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    if (_hasKeyboard) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _searchFocus.requestFocus() : null);
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _add(Product p) async {
    if (p.usesSerials) {
      final line = ref.read(cartProvider).lines.where((l) => l.product.id == p.id).firstOrNull;
      final picked = await showSerialPicker(
        context,
        productId: p.id,
        productName: p.name,
        branchId: ref.read(currentUserProvider).branchId,
        selected: line?.serials ?? const [],
      );
      if (picked != null) ref.read(cartProvider.notifier).setSerials(p, picked);
      return;
    }
    final err = ref.read(cartProvider.notifier).add(p);
    if (err != null) {
      showToast(context, err, error: true);
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// Barcode scanners type the code and press Enter; an exact match goes straight to the cart.
  Future<void> _submitCode(String code) async {
    if (code.isEmpty) return;
    try {
      final p = await ref.read(productRepoProvider).findByCode(code);
      if (!mounted) return;
      if (p != null) {
        _add(p);
        _search.clear();
        setState(() => _q = '');
        _searchFocus.requestFocus();
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context, title: 'Scan product');
    if (code == null || !mounted) return;
    try {
      final p = await ref.read(productRepoProvider).findByCode(code);
      if (!mounted) return;
      if (p == null) {
        showToast(context, 'No product found for "$code".', error: true);
      } else {
        _add(p);
        showToast(context, '${p.name} added');
      }
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  void _openCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (ctx) => _CartSheet(onClose: () => Navigator.pop(ctx)),
    );
  }

  Future<void> _pickCustomer() async {
    final pick = await showCustomerPicker(context);
    if (pick != null) ref.read(cartProvider.notifier).setCustomer(pick.customer);
  }

  Future<void> _holdCurrent() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      showToast(context, 'The cart is empty, so there is nothing to hold.');
      return;
    }
    await ref.read(heldCartsProvider.notifier).hold(cart);
    ref.read(cartProvider.notifier).clear();
    if (mounted) showToast(context, 'Sale put on hold');
  }

  void _charge() {
    if (ref.read(cartProvider).isEmpty) {
      showToast(context, 'Add a product before charging.');
      return;
    }
    showCheckout(context, ref);
  }

  /// Escape clears the search box so the next scan starts clean.
  void _escape() {
    if (_search.text.isNotEmpty) {
      _search.clear();
      setState(() => _q = '');
    }
    _searchFocus.requestFocus();
  }

  static const _shortcuts = <(String, String)>[
    ('F2  or  Ctrl + K', 'Go to the search and scan box'),
    ('Enter (in the search box)', 'Add the product with that exact barcode or SKU'),
    ('F4', 'Choose the customer'),
    ('F6', 'Hold the current sale'),
    ('F7', 'Open held sales'),
    ('F9  or  Ctrl + Enter', 'Charge: open the payment screen'),
    ('Esc', 'Clear the search box'),
    ('F1', 'Show this list'),
  ];

  void _showShortcuts() {
    showAppSheet<void>(
      context,
      title: 'Keyboard shortcuts',
      builder: (ctx) => Column(
        children: [
          for (final k in _shortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 190, child: Text(k.$1, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Expanded(child: Text(k.$2)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _openHeld() {
    showAppSheet<void>(context, title: 'Held sales', builder: (_) => const _HeldCartsList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = Breakpoints.isWide(context);
    final cart = ref.watch(cartProvider);
    final held = ref.watch(heldCartsProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final products = ref.watch(productsProvider((search: _q, categoryId: _categoryId, limit: 150, includeInactive: false)));

    final browser = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  controller: _search,
                  focusNode: _searchFocus,
                  hint: 'Search or scan product',
                  debounce: const Duration(milliseconds: 250),
                  onChanged: (v) => setState(() => _q = v),
                  onSubmitted: _submitCode,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _scan, tooltip: 'Scan with camera', icon: const Icon(Icons.qr_code_scanner_rounded)),
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
                child: ChoiceChip(label: const Text('All'), selected: _categoryId == null, onSelected: (_) => setState(() => _categoryId = null)),
              ),
              for (final cat in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat.name),
                    selected: _categoryId == cat.id,
                    onSelected: (_) => setState(() => _categoryId = _categoryId == cat.id ? null : cat.id),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody<List<Product>>(
            value: products,
            onRetry: () => ref.invalidate(productsProvider),
            loading: const Center(child: CircularProgressIndicator()),
            builder: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No products found',
                  message: _q.isEmpty ? 'Add products in Inventory to start selling.' : 'Try another name, SKU or barcode.',
                );
              }
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(16, 8, 16, wide ? 24 : 100),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 178,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => _ProductCard(product: items[i], onTap: () => _add(items[i])),
              );
            },
          ),
        ),
      ],
    );

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f1): _showShortcuts,
      const SingleActivator(LogicalKeyboardKey.f2): _searchFocus.requestFocus,
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): _searchFocus.requestFocus,
      const SingleActivator(LogicalKeyboardKey.f4): _pickCustomer,
      const SingleActivator(LogicalKeyboardKey.f6): _holdCurrent,
      const SingleActivator(LogicalKeyboardKey.f7): _openHeld,
      const SingleActivator(LogicalKeyboardKey.f9): _charge,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _charge,
      const SingleActivator(LogicalKeyboardKey.escape): _escape,
    };

    // Shortcuts work from anywhere on this screen, also while the search box has focus. They stop while a sheet or
    // dialog is open, because those sit above this screen.
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(
        title: const Text('Point of sale'),
        actions: [
          if (wide) IconButton(icon: const Icon(Icons.keyboard_alt_outlined), tooltip: 'Keyboard shortcuts (F1)', onPressed: _showShortcuts),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(icon: const Icon(Icons.pause_circle_outline_rounded), tooltip: 'Held sales', onPressed: _openHeld),
              if (held.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
                    child: Text('${held.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                Expanded(child: browser),
                Container(
                  width: 420,
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))),
                  child: const CartPanel(),
                ),
              ],
            )
          : browser,
      bottomNavigationBar: wide || cart.isEmpty
          ? null
          : Container(
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SafeArea(
                top: false,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openCart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                          child: Text('${Fmt.qty(cart.quantity)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 12),
                        const Text('View cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        const Spacer(),
                        Text(Fmt.money(cart.totals.total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(width: 6),
                        const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ),
      ),
    );
  }
}

class _CartSheet extends ConsumerWidget {
  const _CartSheet({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<CartState>(cartProvider, (prev, next) {
      if (next.isEmpty && prev != null && !prev.isEmpty) onClose();
    });
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.92, child: CartPanel(onClose: onClose)),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final inCart = ref.watch(cartProvider.select((cart) {
      for (final l in cart.lines) {
        if (l.product.id == product.id) return l.qty;
      }
      return 0.0;
    }));
    final unavailable = product.outOfStock;
    return Opacity(
      opacity: unavailable ? 0.55 : 1,
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        borderColor: inCart > 0 ? c.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: c.surfaceMuted,
                    child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                        ? Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_outlined, color: c.textMuted, size: 30))
                        : Icon(Icons.inventory_2_outlined, color: c.textMuted, size: 30),
                  ),
                  if (inCart > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(10)),
                        child: Text(Fmt.qty(inCart), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                  Positioned(left: 8, bottom: 8, child: StockPill(product: product)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  MoneyText(product.sellingPrice, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeldCartsList extends ConsumerWidget {
  const _HeldCartsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final held = ref.watch(heldCartsProvider);
    if (held.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No held sales. Use Hold in the cart to park a sale and serve the next customer.'));
    }
    return Column(
      children: [
        for (final h in held)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text('${h.cart.itemCount} items  |  ${Fmt.money(h.cart.totals.total)}  |  ${Fmt.time(h.createdAt)}',
                            style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                        if (h.cart.customer != null) Text(h.cart.customer!.name, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                      ],
                    ),
                  ),
                  AppButton('Resume', dense: true, onPressed: () async {
                    final current = ref.read(cartProvider);
                    if (!current.isEmpty) await ref.read(heldCartsProvider.notifier).hold(current);
                    ref.read(cartProvider.notifier).restore(h.cart);
                    await ref.read(heldCartsProvider.notifier).discard(h.id);
                    if (context.mounted) Navigator.pop(context);
                  }),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                    onPressed: () => ref.read(heldCartsProvider.notifier).discard(h.id),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
