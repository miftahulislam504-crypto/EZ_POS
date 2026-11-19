import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/json.dart';
import 'providers.dart';

class UnitModel {
  const UnitModel({required this.id, required this.name, required this.shortName, this.allowDecimal = false});

  final String id;
  final String name;
  final String shortName;
  final bool allowDecimal;

  factory UnitModel.fromJson(Map<String, dynamic> j) => UnitModel(
        id: j['id'] as String,
        name: j['name'] as String,
        shortName: j['short_name'] as String,
        allowDecimal: j['allow_decimal'] == true,
      );
}

class Category {
  const Category({required this.id, required this.name, this.parentId, this.isActive = true});

  final String id;
  final String name;
  final String? parentId;
  final bool isActive;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        parentId: j['parent_id'] as String?,
        isActive: j['is_active'] != false,
      );
}

class Brand {
  const Brand({required this.id, required this.name});

  final String id;
  final String name;

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(id: j['id'] as String, name: j['name'] as String);
}

class PaymentAccount {
  const PaymentAccount({
    required this.id,
    required this.name,
    required this.type,
    this.accountNo,
    this.balance = 0,
    this.openingBalance = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String type; // cash, bank, mfs, card, other
  final String? accountNo;
  final double balance;
  final double openingBalance;
  final bool isActive;

  bool get isCash => type == 'cash';

  factory PaymentAccount.fromJson(Map<String, dynamic> j) => PaymentAccount(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['account_type'] as String,
        accountNo: j['account_no'] as String?,
        balance: dbl(j['balance']),
        openingBalance: dbl(j['opening_balance']),
        isActive: j['is_active'] != false,
      );
}

class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory ExpenseCategory.fromJson(Map<String, dynamic> j) =>
      ExpenseCategory(id: j['id'] as String, name: j['name'] as String);
}

final unitsProvider = FutureProvider<List<UnitModel>>((ref) async {
  ref.watch(userIdProvider);
  final rows = await ref.watch(supabaseProvider).from('units').select().order('name');
  return [for (final r in rows) UnitModel.fromJson(r)];
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  ref.watch(userIdProvider);
  final rows = await ref.watch(supabaseProvider).from('categories').select().order('name');
  return [for (final r in rows) Category.fromJson(r)];
});

final brandsProvider = FutureProvider<List<Brand>>((ref) async {
  ref.watch(userIdProvider);
  final rows = await ref.watch(supabaseProvider).from('brands').select().order('name');
  return [for (final r in rows) Brand.fromJson(r)];
});

/// Active payment methods with live balances (cash, bKash, Nagad, bank and so on).
final paymentAccountsProvider = FutureProvider<List<PaymentAccount>>((ref) async {
  ref.watch(userIdProvider);
  final rows = await ref.watch(supabaseProvider).from('accounts_view').select().order('sort_order').order('name');
  return [for (final r in rows) PaymentAccount.fromJson(r)];
});

final expenseCategoriesProvider = FutureProvider<List<ExpenseCategory>>((ref) async {
  ref.watch(userIdProvider);
  final rows = await ref
      .watch(supabaseProvider)
      .from('expense_categories')
      .select()
      .eq('is_active', true)
      .order('name');
  return [for (final r in rows) ExpenseCategory.fromJson(r)];
});

/// Writes for catalog-style tables. Every call is scoped to the signed-in business.
class CatalogRepository {
  CatalogRepository(this._client, this._businessId);

  final SupabaseClient _client;
  final String _businessId;

  Future<void> saveCategory({String? id, required String name, String? parentId}) async {
    final data = {'name': name.trim(), 'parent_id': parentId};
    if (id == null) {
      await _client.from('categories').insert({...data, 'business_id': _businessId});
    } else {
      await _client.from('categories').update(data).eq('id', id);
    }
  }

  Future<void> deleteCategory(String id) => _client.from('categories').delete().eq('id', id);

  Future<void> saveBrand({String? id, required String name}) async {
    if (id == null) {
      await _client.from('brands').insert({'name': name.trim(), 'business_id': _businessId});
    } else {
      await _client.from('brands').update({'name': name.trim()}).eq('id', id);
    }
  }

  Future<void> deleteBrand(String id) => _client.from('brands').delete().eq('id', id);

  Future<void> saveUnit({String? id, required String name, required String shortName, required bool allowDecimal}) async {
    final data = {'name': name.trim(), 'short_name': shortName.trim(), 'allow_decimal': allowDecimal};
    if (id == null) {
      await _client.from('units').insert({...data, 'business_id': _businessId});
    } else {
      await _client.from('units').update(data).eq('id', id);
    }
  }

  Future<void> deleteUnit(String id) => _client.from('units').delete().eq('id', id);

  Future<void> saveExpenseCategory({String? id, required String name}) async {
    if (id == null) {
      await _client.from('expense_categories').insert({'name': name.trim(), 'business_id': _businessId});
    } else {
      await _client.from('expense_categories').update({'name': name.trim()}).eq('id', id);
    }
  }

  Future<void> savePaymentAccount({
    String? id,
    required String name,
    required String type,
    String? accountNo,
    double openingBalance = 0,
    bool isActive = true,
  }) async {
    final data = {
      'name': name.trim(),
      'account_type': type,
      'account_no': nonEmpty(accountNo),
      'is_active': isActive,
    };
    if (id == null) {
      await _client.from('payment_accounts').insert({...data, 'opening_balance': openingBalance, 'business_id': _businessId});
    } else {
      await _client.from('payment_accounts').update(data).eq('id', id);
    }
  }
}

final catalogRepoProvider = Provider<CatalogRepository>((ref) {
  final user = ref.watch(currentUserProvider);
  return CatalogRepository(ref.watch(supabaseProvider), user.businessId);
});

typedef PartyOption = ({String id, String name});

final supplierOptionsProvider = FutureProvider<List<PartyOption>>((ref) async {
  ref.watch(userIdProvider);
  final rows = await ref.watch(supabaseProvider).from('suppliers').select('id, name').eq('is_active', true).order('name');
  return [for (final r in rows) (id: r['id'] as String, name: r['name'] as String)];
});

/// "Parent / Child" labels, parents first, for pickers.
List<({String id, String label})> categoryLabels(List<Category> all) {
  final byId = {for (final c in all) c.id: c};
  final out = [
    for (final c in all)
      (id: c.id, label: c.parentId != null && byId[c.parentId] != null ? '${byId[c.parentId]!.name} / ${c.name}' : c.name),
  ];
  out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return out;
}
