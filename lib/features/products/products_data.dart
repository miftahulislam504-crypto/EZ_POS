import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/data/providers.dart';
import '../../core/utils/json.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brandName,
    this.model,
    this.unitId,
    this.unitName,
    this.productType = 'standard',
    this.trackStock = true,
    this.purchasePrice = 0,
    this.avgCost = 0,
    this.sellingPrice = 0,
    this.wholesalePrice,
    this.minSellingPrice,
    this.taxRate = 0,
    this.warrantyMonths,
    this.description,
    this.imageUrl,
    this.supplierId,
    this.lowStockLimit = 0,
    this.isActive = true,
    this.stock = 0,
    this.damaged = 0,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? categoryId;
  final String? categoryName;
  final String? brandId;
  final String? brandName;
  final String? model;
  final String? unitId;
  final String? unitName;
  final String productType;
  final bool trackStock;
  final double purchasePrice;
  final double avgCost;
  final double sellingPrice;
  final double? wholesalePrice;
  final double? minSellingPrice;
  final double taxRate;
  final int? warrantyMonths;
  final String? description;
  final String? imageUrl;
  final String? supplierId;
  final double lowStockLimit;
  final bool isActive;
  final double stock;
  final double damaged;

  bool get isService => !trackStock;
  bool get outOfStock => trackStock && stock <= 0;
  bool get lowStock => trackStock && stock > 0 && lowStockLimit > 0 && stock <= lowStockLimit;

  factory Product.fromRow(Map<String, dynamic> j) {
    var stock = 0.0;
    var damaged = 0.0;
    for (final s in (j['stock_levels'] as List? ?? const [])) {
      stock += dbl(s['quantity']);
      damaged += dbl(s['damaged_quantity']);
    }
    return Product(
      id: j['id'] as String,
      name: j['name'] as String,
      sku: j['sku'] as String?,
      barcode: j['barcode'] as String?,
      categoryId: j['category_id'] as String?,
      categoryName: (j['categories'] as Map?)?['name'] as String?,
      brandId: j['brand_id'] as String?,
      brandName: (j['brands'] as Map?)?['name'] as String?,
      model: j['model'] as String?,
      unitId: j['unit_id'] as String?,
      unitName: (j['units'] as Map?)?['short_name'] as String?,
      productType: (j['product_type'] as String?) ?? 'standard',
      trackStock: j['track_stock'] != false,
      purchasePrice: dbl(j['purchase_price']),
      avgCost: dbl(j['avg_cost']),
      sellingPrice: dbl(j['selling_price']),
      wholesalePrice: dblOrNull(j['wholesale_price']),
      minSellingPrice: dblOrNull(j['min_selling_price']),
      taxRate: dbl(j['tax_rate']),
      warrantyMonths: j['warranty_months'] == null ? null : intOf(j['warranty_months']),
      description: j['description'] as String?,
      imageUrl: j['image_url'] as String?,
      supplierId: j['supplier_id'] as String?,
      lowStockLimit: dbl(j['low_stock_limit']),
      isActive: j['is_active'] != false,
      stock: stock,
      damaged: damaged,
    );
  }

  /// Compact form kept with held carts so they survive an app restart.
  Map<String, dynamic> toCache() => {
        'id': id,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'unit': unitName,
        'track_stock': trackStock,
        'cost': avgCost,
        'price': sellingPrice,
        'wholesale': wholesalePrice,
        'min_price': minSellingPrice,
        'tax': taxRate,
        'image': imageUrl,
        'stock': stock,
        'category': categoryName,
      };

  factory Product.fromCache(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        sku: j['sku'] as String?,
        barcode: j['barcode'] as String?,
        unitName: j['unit'] as String?,
        trackStock: j['track_stock'] != false,
        avgCost: dbl(j['cost']),
        sellingPrice: dbl(j['price']),
        wholesalePrice: dblOrNull(j['wholesale']),
        minSellingPrice: dblOrNull(j['min_price']),
        taxRate: dbl(j['tax']),
        imageUrl: j['image'] as String?,
        stock: dbl(j['stock']),
        categoryName: j['category'] as String?,
      );
}

typedef ProductQuery = ({String search, String? categoryId, int limit, bool includeInactive});

const productSelect = '*, categories(name), brands(name), units(short_name), stock_levels(quantity, damaged_quantity)';

class ProductRepository {
  ProductRepository(this._client, this._businessId);

  final SupabaseClient _client;
  final String _businessId;

  Future<List<Product>> list(ProductQuery q) async {
    var query = _client.from('products').select(productSelect);
    if (!q.includeInactive) query = query.eq('is_active', true);
    if (q.categoryId != null) query = query.eq('category_id', q.categoryId!);
    final s = safeSearch(q.search);
    if (s.isNotEmpty) query = query.or('name.ilike.%$s%,sku.ilike.%$s%,barcode.ilike.%$s%,model.ilike.%$s%');
    final rows = await query.order('name').limit(q.limit);
    return [for (final r in rows) Product.fromRow(r)];
  }

  /// Exact match on barcode or SKU, used by scanners and the POS search box.
  Future<Product?> findByCode(String code) async {
    final s = safeSearch(code);
    if (s.isEmpty) return null;
    final rows = await _client
        .from('products')
        .select(productSelect)
        .eq('is_active', true)
        .or('barcode.eq.$s,sku.eq.$s')
        .limit(1);
    return rows.isEmpty ? null : Product.fromRow(rows.first);
  }

  Future<Product?> byId(String id) async {
    final row = await _client.from('products').select(productSelect).eq('id', id).maybeSingle();
    return row == null ? null : Product.fromRow(row);
  }

  Future<String> save(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      final row = await _client.from('products').insert({...data, 'business_id': _businessId}).select('id').single();
      return row['id'] as String;
    }
    await _client.from('products').update(data).eq('id', id);
    return id;
  }

  Future<void> setActive(String id, bool active) => _client.from('products').update({'is_active': active}).eq('id', id);

  Future<String> uploadImage(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final path = '$_businessId/${const Uuid().v4()}.$ext';
    await _client.storage.from('product-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}', upsert: false),
        );
    return _client.storage.from('product-images').getPublicUrl(path);
  }
}

final productRepoProvider = Provider<ProductRepository>((ref) {
  final user = ref.watch(currentUserProvider);
  return ProductRepository(ref.watch(supabaseProvider), user.businessId);
});

final productsProvider = FutureProvider.autoDispose.family<List<Product>, ProductQuery>((ref, q) {
  return ref.watch(productRepoProvider).list(q);
});

final productByIdProvider = FutureProvider.autoDispose.family<Product?, String>((ref, id) {
  return ref.watch(productRepoProvider).byId(id);
});
