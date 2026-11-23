import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../auth/auth_pages.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.path, this.allowed, {this.mobile = false});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final bool Function(AppUser) allowed;
  final bool mobile;
}

final _destinations = <_Dest>[
  _Dest('Home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, '/dashboard', (u) => u.can(Perm.dashboardView), mobile: true),
  _Dest('POS', Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, '/pos', (u) => u.can(Perm.salesCreate), mobile: true),
  _Dest('Transactions', Icons.receipt_long_outlined, Icons.receipt_long_rounded, '/transactions',
      (u) => u.canAny([Perm.salesView, Perm.purchasesView, Perm.customersView, Perm.suppliersView]), mobile: true),
  _Dest('Inventory', Icons.inventory_2_outlined, Icons.inventory_2_rounded, '/inventory', (u) => u.canAny([Perm.productsView, Perm.inventoryView]), mobile: true),
  _Dest('Installments', Icons.event_repeat_outlined, Icons.event_repeat_rounded, '/installments', (u) => u.can(Perm.installmentsView)),
  _Dest('Cash', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, '/cash', (u) => u.can(Perm.cashView)),
  _Dest('Customers', Icons.people_alt_outlined, Icons.people_alt_rounded, '/customers', (u) => u.can(Perm.customersView)),
  _Dest('Suppliers', Icons.local_shipping_outlined, Icons.local_shipping_rounded, '/suppliers', (u) => u.can(Perm.suppliersView)),
  _Dest('Expenses', Icons.payments_outlined, Icons.payments_rounded, '/expenses', (u) => u.can(Perm.expensesView)),
  _Dest('Reports', Icons.bar_chart_outlined, Icons.bar_chart_rounded, '/reports', (u) => u.can(Perm.reportsView)),
  _Dest('Settings', Icons.settings_outlined, Icons.settings_rounded, '/settings', (u) => true),
];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  bool _active(String path) => location == path || location.startsWith('$path/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final wide = Breakpoints.isWide(context);

    if (wide) {
      final items = _destinations.where((d) => d.allowed(user)).toList();
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(user: user, items: items, isActive: _active),
            Expanded(child: child),
          ],
        ),
      );
    }

    final mobile = <_Dest>[..._destinations.where((d) => d.mobile && d.allowed(user)), _Dest('More', Icons.grid_view_outlined, Icons.grid_view_rounded, '/more', (_) => true)];
    var index = mobile.indexWhere((d) => d.path != '/more' && _active(d.path));
    if (index < 0) index = mobile.length - 1;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.border))),
        child: NavigationBar(
          selectedIndex: index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => context.go(mobile[i].path),
          destinations: [
            for (final d in mobile) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.user, required this.items, required this.isActive});

  final AppUser user;
  final List<_Dest> items;
  final bool Function(String) isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      width: 252,
      color: c.sidebar,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Row(
                children: [
                  const BrandMark(size: 40, inverted: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EZ POS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2)),
                        Text(user.business.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.sidebarMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final d in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _NavTile(dest: d, selected: isActive(d.path)),
                    ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.sidebarActive.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Avatar(user.fullName, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(user.roleLabel, style: TextStyle(color: c.sidebarMuted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    icon: Icon(Icons.logout_rounded, color: c.sidebarMuted, size: 20),
                    onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({required this.dest, required this.selected});

  final _Dest dest;
  final bool selected;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? c.sidebarActive : (_hover ? c.sidebarActive.withValues(alpha: 0.45) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go(widget.dest.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(selected ? widget.dest.selectedIcon : widget.dest.icon, size: 21, color: selected ? Colors.white : c.sidebarMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.dest.label,
                      style: TextStyle(color: selected ? Colors.white : c.sidebarText.withValues(alpha: 0.85), fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
                ),
                if (selected) Container(width: 4, height: 18, decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
