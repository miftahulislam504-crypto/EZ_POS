import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_user.dart';
import '../../core/data/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../customers/customers_data.dart';
import '../customers/party_widgets.dart';

class CustomerPick {
  const CustomerPick(this.customer);
  final Customer? customer; // null = walk-in
}

/// Returns a [CustomerPick] (null customer means walk-in) or null when dismissed.
Future<CustomerPick?> showCustomerPicker(BuildContext context) {
  return showAppSheet<CustomerPick>(context, title: 'Select customer', maxWidth: 560, builder: (_) => const _CustomerPicker());
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(customersProvider((search: _q, filter: 'all', limit: 30)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(hint: 'Search name or phone', autofocus: true, onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const IconBadge(Icons.person_outline_rounded, tone: Tone.neutral),
          title: const Text('Walk-in customer', style: TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => Navigator.pop(context, const CustomerPick(null)),
        ),
        value.when(
          data: (items) => Column(
            children: [
              for (final c in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(c.name, size: 40),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(c.phone ?? c.code ?? ''),
                  trailing: c.balance.abs() > 0.004 ? BalanceLabel(c.balance) : null,
                  onTap: () => Navigator.pop(context, CustomerPick(c)),
                ),
            ],
          ),
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
        ),
        if (user.can(Perm.customersManage))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppButton('Add new customer', icon: Icons.person_add_alt_1_rounded, kind: ButtonKind.secondary, onPressed: () {
              Navigator.pop(context);
              context.push('/customers/new');
            }),
          ),
      ],
    );
  }
}
