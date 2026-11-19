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
import 'customers_data.dart';
import 'party_widgets.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String _q = '';
  String _filter = 'all';
  int _limit = AppConfig.listPageSize;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(customersProvider((search: _q, filter: _filter, limit: _limit)));

    return PageScaffold(
      title: 'Customers',
      floatingActionButton: user.can(Perm.customersManage)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/customers/new'),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add customer'),
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
                for (final f in const [('all', 'All'), ('due', 'With due'), ('advance', 'With advance'), ('inactive', 'Inactive')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Customer>>(
              value: value,
              onRetry: () => ref.invalidate(customersProvider),
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: _q.isEmpty && _filter == 'all' ? 'No customers yet' : 'No customers found',
                    message: _q.isEmpty && _filter == 'all' ? 'Add customers to track their purchases and dues.' : 'Try a different search or filter.',
                    actionLabel: _q.isEmpty && _filter == 'all' && user.can(Perm.customersManage) ? 'Add customer' : null,
                    onAction: () => context.push('/customers/new'),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(customersProvider),
                  child: AdaptiveList(
                    rowHeight: 76,
                    itemCount: items.length,
                    footer: items.length >= _limit ? LoadMoreFooter(onPressed: () => setState(() => _limit += AppConfig.listPageSize)) : null,
                    itemBuilder: (_, i) {
                      final c = items[i];
                      final colors = context.colors;
                      return AppCard(
                        onTap: () => context.push('/customers/${c.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Avatar(c.name, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text([if (c.phone != null) c.phone!, if (c.code != null) c.code!].join('  |  '),
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: colors.textMuted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (c.group != 'regular') ...[StatusPill(c.groupLabel, tone: Tone.brand, dense: true), const SizedBox(width: 8)],
                            BalanceLabel(c.balance),
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
