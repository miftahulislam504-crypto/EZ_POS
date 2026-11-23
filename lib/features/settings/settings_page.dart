import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final mode = ref.watch(themeModeProvider);
    final c = context.colors;

    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap, {Tone tone = Tone.brand}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                IconBadge(icon, tone: tone, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(subtitle, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textMuted),
              ],
            ),
          ),
        );

    return PageScaffold(
      title: 'Settings',
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          AppCard(
            child: Row(
              children: [
                Avatar(user.business.name, size: 52, imageUrl: user.business.logoUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.business.name, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text('${user.fullName}  |  ${user.roleLabel}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (user.can(Perm.settingsManage)) ...[
            const SectionHeader('Business'),
            tile(Icons.storefront_outlined, 'Business profile', 'Name, logo, address and contact', () => context.push('/settings/business')),
            tile(Icons.tune_rounded, 'Sales and stock rules', 'Invoice numbering, credit sales, return period, security', () => context.push('/settings/sales')),
            tile(Icons.print_outlined, 'Receipt and printer', 'Paper size, footer message and terms', () => context.push('/settings/receipt')),
            tile(Icons.qr_code_2_rounded, 'SKU and barcode rules', 'Product code prefix, number length and barcode prefix', () => context.push('/settings/product-rules'), tone: Tone.info),
            tile(Icons.account_balance_wallet_outlined, 'Payment methods', 'Cash, bKash, Nagad, bank and card accounts', () => context.push('/settings/payment-methods')),
            tile(Icons.event_repeat_rounded, 'Installments', 'Defaults, reminders and agreement terms', () => context.push('/settings/installments'), tone: Tone.brand),
            tile(Icons.store_mall_directory_outlined, 'Branches and counters', 'Branches, warehouses and cash counters', () => context.push('/settings/branches'), tone: Tone.info),
          ],
          if (user.can(Perm.productsManage))
            tile(Icons.category_outlined, 'Catalog setup', 'Categories, brands and units', () => context.push('/settings/catalog'), tone: Tone.info),
          if (user.can(Perm.usersManage)) ...[
            const SectionHeader('Team'),
            tile(Icons.groups_outlined, 'Team members', 'Add staff and manage access', () => context.push('/settings/team'), tone: Tone.warning),
            tile(Icons.admin_panel_settings_outlined, 'Roles and permissions', 'Choose what each role can do', () => context.push('/settings/roles'), tone: Tone.warning),
          ],
          const SectionHeader('This device'),
          tile(Icons.print_outlined, 'Printer on this device', 'Print receipts straight to a Bluetooth, USB or network thermal printer', () => context.push('/settings/printer'), tone: Tone.info),
          const SectionHeader('Appearance'),
          AppCard(
            padding: const EdgeInsets.all(14),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          const SectionHeader('Account'),
          tile(Icons.logout_rounded, 'Sign out', 'You will need to sign in again', () async {
            if (await confirmDialog(context, title: 'Sign out?', message: 'Held sales stay on this device.', confirmLabel: 'Sign out')) {
              await ref.read(supabaseProvider).auth.signOut();
            }
          }, tone: Tone.danger),
          const SizedBox(height: 16),
          Center(child: Text('EZ POS 1.0  |  Phase 1', style: context.text.bodySmall?.copyWith(color: c.textMuted))),
        ],
      ),
    );
  }
}
