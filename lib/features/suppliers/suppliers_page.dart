import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../customers/party_widgets.dart';
import 'suppliers_data.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  String _q = '';
  String _filter = 'all';
  int _limit = AppConfig.listPageSize;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(suppliersProvider((search: _q, filter: _filter, limit: _limit)));
    return PageScaffold(
      title: 'Suppliers',
      floatingActionButton: user.can(Perm.suppliersManage)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/suppliers/new'),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add supplier'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchField(hint: 'Search name, phone or code', onChanged: (v) => setState(() { _q = v; _limit = AppConfig.listPageSize; })),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in const [('all', 'All'), ('due', 'We owe'), ('advance', 'Advance paid'), ('inactive', 'Inactive')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Supplier>>(
              value: value,
              onRetry: () => ref.invalidate(suppliersProvider),
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: _q.isEmpty && _filter == 'all' ? 'No suppliers yet' : 'No suppliers found',
                    message: _q.isEmpty && _filter == 'all' ? 'Add the suppliers you buy stock from.' : 'Try a different search or filter.',
                    actionLabel: _q.isEmpty && _filter == 'all' && user.can(Perm.suppliersManage) ? 'Add supplier' : null,
                    onAction: () => context.push('/suppliers/new'),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(suppliersProvider),
                  child: AdaptiveList(
                    rowHeight: 76,
                    itemCount: items.length,
                    footer: items.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize)) : null,
                    itemBuilder: (_, i) {
                      final s = items[i];
                      return AppCard(
                        onTap: () => context.push('/suppliers/${s.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Avatar(s.name, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text([if (s.contactPerson != null) s.contactPerson!, if (s.phone != null) s.phone!].join('  |  '),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.colors.textMuted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            BalanceLabel(s.balance, kind: PartyKind.supplier),
                          ],
                        ),
                      );
                    },
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
