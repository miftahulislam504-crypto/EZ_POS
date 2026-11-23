import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/barcodes.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/barcode_scanner_page.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../dashboard/dashboard_data.dart';
import '../inventory/inventory_data.dart';
import 'products_data.dart';
import 'products_tab.dart';

class ProductFormPage extends ConsumerWidget {
  const ProductFormPage({super.key, this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (productId == null) return const _ProductForm();
    final product = ref.watch(productByIdProvider(productId!));
    return product.when(
      data: (p) => p == null
          ? const Scaffold(body: EmptyState(icon: Icons.search_off_rounded, title: 'Product not found'))
          : _ProductForm(product: p),
      loading: () => Scaffold(appBar: AppBar(title: const Text('Edit product')), body: const ListSkeleton(rows: 5)),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit product')),
        body: ErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(productByIdProvider)),
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.product});

  final Product? product;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _model;
  late final TextEditingController _purchase;
  late final TextEditingController _selling;
  late final TextEditingController _wholesale;
  late final TextEditingController _minPrice;
  late final TextEditingController _tax;
  late final TextEditingController _warranty;
  late final TextEditingController _description;
  late final TextEditingController _lowStock;
  final _openingStock = TextEditingController();

  String? _categoryId;
  String? _brandId;
  String? _unitId;
  String? _supplierId;
  bool _trackStock = true;
  String _tracking = 'none';
  bool _isActive = true;
  String? _imageUrl;
  Uint8List? _newImage;
  String _newImageExt = 'jpg';
  bool _saving = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    String numText(double? v) => v == null || v == 0 ? '' : Fmt.qty(v);
    _name = TextEditingController(text: p?.name ?? '');
    _sku = TextEditingController(text: p?.sku ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _model = TextEditingController(text: p?.model ?? '');
    _purchase = TextEditingController(text: numText(p?.purchasePrice));
    _selling = TextEditingController(text: numText(p?.sellingPrice));
    _wholesale = TextEditingController(text: numText(p?.wholesalePrice));
    _minPrice = TextEditingController(text: numText(p?.minSellingPrice));
    final defaultTax = p == null ? (ref.read(currentUserProvider).business.settings['default_tax_rate'] as num?)?.toDouble() : null;
    _tax = TextEditingController(text: p != null ? numText(p.taxRate) : numText(defaultTax));
    _warranty = TextEditingController(text: p?.warrantyMonths?.toString() ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _lowStock = TextEditingController(text: numText(p?.lowStockLimit));
    _categoryId = p?.categoryId;
    _brandId = p?.brandId;
    _unitId = p?.unitId;
    _supplierId = p?.supplierId;
    _trackStock = p?.trackStock ?? true;
    _tracking = p?.trackingType ?? 'none';
    _isActive = p?.isActive ?? true;
    _imageUrl = p?.imageUrl;
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _barcode, _model, _purchase, _selling, _wholesale, _minPrice, _tax, _warranty, _description, _lowStock, _openingStock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1200, imageQuality: 82);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final dot = file.name.lastIndexOf('.');
    setState(() {
      _newImage = bytes;
      _newImageExt = dot >= 0 ? file.name.substring(dot + 1).toLowerCase() : 'jpg';
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(_newImageExt)) _newImageExt = 'jpg';
    });
  }

  Future<void> _chooseImage() async {
    await showAppSheet<void>(
      context,
      title: 'Product photo',
      builder: (ctx) => Column(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
          ),
          if (_newImage != null || (_imageUrl ?? '').isNotEmpty)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
              title: Text('Remove photo', style: TextStyle(color: context.colors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _newImage = null;
                  _imageUrl = null;
                });
              },
            ),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code != null) setState(() => _barcode.text = code);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final selling = Fmt.parse(_selling.text);
    final minPrice = Fmt.parse(_minPrice.text);
    if (_minPrice.text.trim().isNotEmpty && minPrice > selling) {
      showToast(context, 'Minimum selling price cannot be higher than the selling price.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(productRepoProvider);
      var imageUrl = _imageUrl;
      if (_newImage != null) imageUrl = await repo.uploadImage(_newImage!, _newImageExt);

      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'sku': nonEmpty(_sku.text),
        'barcode': nonEmpty(_barcode.text),
        'category_id': _categoryId,
        'brand_id': _brandId,
        'model': nonEmpty(_model.text),
        'unit_id': _unitId,
        'product_type': _trackStock ? 'standard' : 'service',
        'track_stock': _trackStock,
        'tracking_type': _trackStock ? _tracking : 'none',
        'purchase_price': Fmt.parse(_purchase.text),
        'selling_price': selling,
        'wholesale_price': _wholesale.text.trim().isEmpty ? null : Fmt.parse(_wholesale.text),
        'min_selling_price': _minPrice.text.trim().isEmpty ? null : minPrice,
        'tax_rate': Fmt.parse(_tax.text),
        'warranty_months': _warranty.text.trim().isEmpty ? null : int.tryParse(_warranty.text.trim()),
        'description': nonEmpty(_description.text),
        'image_url': imageUrl,
        'supplier_id': _supplierId,
        'low_stock_limit': _trackStock ? Fmt.parse(_lowStock.text) : 0,
        'is_active': _isActive,
      };
      final id = await repo.save(data, id: widget.product?.id);

      final opening = Fmt.parse(_openingStock.text);
      if (!_isEdit && _trackStock && _tracking == 'none' && opening > 0) {
        await ref.read(inventoryRepoProvider).adjust(productId: id, kind: 'opening', quantity: opening, note: 'Opening stock');
      }

      ref.invalidate(productsProvider);
      ref.invalidate(productByIdProvider);
      ref.invalidate(stockReportProvider);
      ref.invalidate(dashboardSummaryProvider);
      if (mounted) {
        context.pop();
        showToast(context, _isEdit ? 'Product updated' : 'Product added');
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
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final brands = ref.watch(brandsProvider).valueOrNull ?? const <Brand>[];
    final units = ref.watch(unitsProvider).valueOrNull ?? const <UnitModel>[];
    final suppliers = ref.watch(supplierOptionsProvider).valueOrNull ?? const <PartyOption>[];

    return FormScaffold(
      title: _isEdit ? 'Edit product' : 'New product',
      formKey: _formKey,
      onSave: _save,
      saving: _saving,
      saveLabel: _isEdit ? 'Save changes' : 'Add product',
      children: [
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _chooseImage,
            child: Stack(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: c.border),
                  ),
                  child: _newImage != null
                      ? Image.memory(_newImage!, fit: BoxFit.cover)
                      : (_imageUrl ?? '').isNotEmpty
                          ? Image.network(_imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))
                          : Icon(Icons.add_a_photo_outlined, color: c.textMuted, size: 32),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        FormSection('Basic information', children: [
          AppTextField(
            controller: _name,
            label: 'Product name',
            hint: 'e.g. Samsung 43" Smart TV',
            validator: Validators.required('Product name'),
            textCapitalization: TextCapitalization.words,
          ),
          FieldRow([
            AppTextField(controller: _sku, label: 'SKU / product code', hint: 'Auto-generated if empty'),
            AppTextField(
              controller: _barcode,
              label: 'Barcode',
              hint: 'Scan or type',
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, size: 20), tooltip: 'Scan', onPressed: _scan),
                  IconButton(
                    icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                    tooltip: 'Generate',
                    onPressed: () => setState(() => _barcode.text = Barcodes.generateEan13(prefix: ref.read(currentUserProvider).business.barcodePrefix)),
                  ),
                ],
              ),
            ),
          ]),
          FieldRow([
            PickerField<String>(
              label: 'Category',
              hint: 'Select category',
              value: _categoryId,
              allowClear: true,
              searchable: true,
              options: [for (final cl in categoryLabels(categories)) PickerOption(cl.id, cl.label)],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            PickerField<String>(
              label: 'Brand',
              hint: 'Select brand',
              value: _brandId,
              allowClear: true,
              searchable: true,
              options: [for (final b in brands) PickerOption(b.id, b.name)],
              onChanged: (v) => setState(() => _brandId = v),
            ),
          ]),
          FieldRow([
            AppTextField(controller: _model, label: 'Model', hint: 'Optional'),
            PickerField<String>(
              label: 'Unit',
              hint: 'Select unit',
              value: _unitId,
              options: [for (final u in units) PickerOption(u.id, '${u.name} (${u.shortName})')],
              onChanged: (v) => setState(() => _unitId = v),
            ),
          ]),
        ]),
        FormSection('Pricing', children: [
          FieldRow([
            MoneyField(controller: _purchase, label: 'Purchase price', validator: Validators.nonNegative('Purchase price')),
            MoneyField(
              controller: _selling,
              label: 'Selling price',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Selling price is required' : Validators.nonNegative('Selling price')(v),
            ),
          ]),
          FieldRow([
            MoneyField(controller: _wholesale, label: 'Wholesale price', validator: Validators.nonNegative('Wholesale price')),
            MoneyField(controller: _minPrice, label: 'Minimum selling price', validator: Validators.nonNegative('Minimum price')),
          ]),
          FieldRow([
            AppTextField(
              controller: _tax,
              label: 'VAT / tax rate (%)',
              hint: '0',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,2}'))],
              validator: (v) {
                final n = Fmt.parse(v);
                return n > 100 ? 'Rate cannot exceed 100%' : null;
              },
            ),
            AppTextField(
              controller: _warranty,
              label: 'Warranty (months)',
              hint: 'Optional',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ]),
        ]),
        FormSection('Stock', children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track inventory', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Turn off for services or items that are not counted.'),
            value: _trackStock,
            onChanged: (v) => setState(() => _trackStock = v),
          ),
          if (_trackStock)
            PickerField<String>(
              label: 'Tracking',
              value: _tracking,
              enabled: !_isEdit || (widget.product?.stock ?? 0) <= 0,
              options: const [
                PickerOption('none', 'Quantity only'),
                PickerOption('imei', 'IMEI (mobile phones)', subtitle: 'Every unit has its own IMEI'),
                PickerOption('serial', 'Serial number', subtitle: 'TV, fridge, laptop and similar'),
                PickerOption('batch', 'Batch', subtitle: 'Batch or lot number'),
                PickerOption('expiry', 'Batch with expiry date', subtitle: 'Sold earliest expiry first'),
              ],
              onChanged: (v) => setState(() => _tracking = v ?? 'none'),
            ),
          if (_trackStock && _isEdit && (widget.product?.stock ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Tracking can be changed only while the product has no stock.', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
            ),
          if (_trackStock && _tracking != 'none' && !_isEdit)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Add stock through a purchase or Adjust stock, where you enter the numbers or batches.', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
            ),
          if (_trackStock)
            FieldRow([
              AppTextField(
                controller: _lowStock,
                label: 'Low stock alert at',
                hint: '0 = off',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (!_isEdit && _tracking == 'none')
                AppTextField(
                  controller: _openingStock,
                  label: 'Opening stock',
                  hint: '0',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                )
              else
                const SizedBox.shrink(),
            ]),
        ]),
        FormSection('More details', children: [
          PickerField<String>(
            label: 'Preferred supplier',
            hint: 'Select supplier',
            value: _supplierId,
            allowClear: true,
            searchable: true,
            options: [for (final s in suppliers) PickerOption(s.id, s.name)],
            onChanged: (v) => setState(() => _supplierId = v),
          ),
          AppTextField(controller: _description, label: 'Description', hint: 'Optional notes', maxLines: 3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Inactive products are hidden from the POS.'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
        ]),
      ],
    );
  }
}
