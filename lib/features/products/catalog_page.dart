import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/common_data.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/data/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

/// Categories, brands and units in one place.
class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: PageScaffold(
        title: 'Catalog setup',
        maxWidth: 820,
        bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Categories'), Tab(text: 'Brands'), Tab(text: 'Units')]),
        body: const TabBarView(children: [_CategoriesTab(), _BrandsTab(), _UnitsTab()]),
      ),
    );
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() action, String done) async {
  try {
    await action();
    if (context.mounted) showToast(context, done);
  } catch (e) {
    if (context.mounted) showToast(context, friendlyError(e), error: true);
  }
}

class _CatalogScaffold extends ConsumerWidget {
  const _CatalogScaffold({required this.empty, required this.onAdd, required this.children, required this.loading});

  final bool loading;
  final String empty;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final can = ref.watch(currentUserProvider).can(Perm.productsManage);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: can ? FloatingActionButton.extended(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add')) : null,
      body: loading
          ? const ListSkeleton(rows: 4)
          : children.isEmpty
              ? EmptyState(icon: Icons.folder_open_rounded, title: empty, actionLabel: can ? 'Add' : null, onAction: onAdd)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, required this.onEdit, required this.onDelete, required this.canEdit});

  final String title;
  final String? subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (subtitle != null) Text(subtitle!, style: context.text.bodySmall?.copyWith(color: context.colors.textMuted)),
                ],
              ),
            ),
            if (canEdit) ...[
              IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: onEdit),
              IconButton(icon: Icon(Icons.delete_outline_rounded, size: 20, color: context.colors.danger), onPressed: onDelete),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(categoriesProvider);
    final can = ref.watch(currentUserProvider).can(Perm.productsManage);
    final all = list.valueOrNull ?? const <Category>[];
    final labels = {for (final l in categoryLabels(all)) l.id: l.label};

    Future<void> edit([Category? existing]) async {
      final name = TextEditingController(text: existing?.name ?? '');
      String? parent = existing?.parentId;
      final saved = await showAppSheet<bool>(
        context,
        title: existing == null ? 'New category' : 'Edit category',
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(controller: name, label: 'Name', autofocus: true, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 14),
              PickerField<String>(
                label: 'Parent category (optional)',
                hint: 'None, top-level category',
                value: parent,
                allowClear: true,
                options: [for (final c in all.where((c) => c.id != existing?.id && c.parentId == null)) PickerOption(c.id, c.name)],
                onChanged: (v) => setState(() => parent = v),
              ),
              const SizedBox(height: 20),
              AppButton('Save', expand: true, onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              }),
            ],
          ),
        ),
      );
      if (saved == true && context.mounted) {
        await _guard(context, () async {
          await ref.read(catalogRepoProvider).saveCategory(id: existing?.id, name: name.text, parentId: parent);
          ref.invalidate(categoriesProvider);
        }, 'Category saved');
      }
    }

    return _CatalogScaffold(
      loading: list.isLoading,
      empty: 'No categories yet',
      onAdd: () => edit(),
      children: [
        for (final c in all)
          _Row(
            title: labels[c.id] ?? c.name,
            canEdit: can,
            onEdit: () => edit(c),
            onDelete: () async {
              if (await confirmDialog(context, title: 'Delete category?', message: 'Products in "${c.name}" will become uncategorised.', confirmLabel: 'Delete', danger: true)) {
                if (context.mounted) {
                  await _guard(context, () async {
                    await ref.read(catalogRepoProvider).deleteCategory(c.id);
                    ref.invalidate(categoriesProvider);
                  }, 'Category deleted');
                }
              }
            },
          ),
      ],
    );
  }
}

class _BrandsTab extends ConsumerWidget {
  const _BrandsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(brandsProvider);
    final can = ref.watch(currentUserProvider).can(Perm.productsManage);

    Future<void> edit([Brand? existing]) async {
      final name = TextEditingController(text: existing?.name ?? '');
      final saved = await showAppSheet<bool>(
        context,
        title: existing == null ? 'New brand' : 'Edit brand',
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(controller: name, label: 'Brand name', autofocus: true, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 20),
            AppButton('Save', expand: true, onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            }),
          ],
        ),
      );
      if (saved == true && context.mounted) {
        await _guard(context, () async {
          await ref.read(catalogRepoProvider).saveBrand(id: existing?.id, name: name.text);
          ref.invalidate(brandsProvider);
        }, 'Brand saved');
      }
    }

    return _CatalogScaffold(
      loading: list.isLoading,
      empty: 'No brands yet',
      onAdd: () => edit(),
      children: [
        for (final b in list.valueOrNull ?? const <Brand>[])
          _Row(
            title: b.name,
            canEdit: can,
            onEdit: () => edit(b),
            onDelete: () async {
              if (await confirmDialog(context, title: 'Delete brand?', message: 'Products of "${b.name}" will have no brand.', confirmLabel: 'Delete', danger: true)) {
                if (context.mounted) {
                  await _guard(context, () async {
                    await ref.read(catalogRepoProvider).deleteBrand(b.id);
                    ref.invalidate(brandsProvider);
                  }, 'Brand deleted');
                }
              }
            },
          ),
      ],
    );
  }
}

class _UnitsTab extends ConsumerWidget {
  const _UnitsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(unitsProvider);
    final can = ref.watch(currentUserProvider).can(Perm.productsManage);

    Future<void> edit([UnitModel? existing]) async {
      final name = TextEditingController(text: existing?.name ?? '');
      final short = TextEditingController(text: existing?.shortName ?? '');
      var decimals = existing?.allowDecimal ?? false;
      final saved = await showAppSheet<bool>(
        context,
        title: existing == null ? 'New unit' : 'Edit unit',
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(controller: name, label: 'Unit name', hint: 'Kilogram', autofocus: true),
              const SizedBox(height: 14),
              AppTextField(controller: short, label: 'Short name', hint: 'kg'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow decimal quantities'),
                value: decimals,
                onChanged: (v) => setState(() => decimals = v),
              ),
              const SizedBox(height: 12),
              AppButton('Save', expand: true, onPressed: () {
                if (name.text.trim().isEmpty || short.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              }),
            ],
          ),
        ),
      );
      if (saved == true && context.mounted) {
        await _guard(context, () async {
          await ref.read(catalogRepoProvider).saveUnit(id: existing?.id, name: name.text, shortName: short.text, allowDecimal: decimals);
          ref.invalidate(unitsProvider);
        }, 'Unit saved');
      }
    }

    return _CatalogScaffold(
      loading: list.isLoading,
      empty: 'No units yet',
      onAdd: () => edit(),
      children: [
        for (final u in list.valueOrNull ?? const <UnitModel>[])
          _Row(
            title: '${u.name} (${u.shortName})',
            subtitle: u.allowDecimal ? 'Decimal quantities allowed' : 'Whole quantities only',
            canEdit: can,
            onEdit: () => edit(u),
            onDelete: () async {
              if (await confirmDialog(context, title: 'Delete unit?', message: 'Products using "${u.name}" will have no unit.', confirmLabel: 'Delete', danger: true)) {
                if (context.mounted) {
                  await _guard(context, () async {
                    await ref.read(catalogRepoProvider).deleteUnit(u.id);
                    ref.invalidate(unitsProvider);
                  }, 'Unit deleted');
                }
              }
            },
          ),
      ],
    );
  }
}
