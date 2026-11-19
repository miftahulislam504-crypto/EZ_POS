import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'settings_data.dart';

class TeamPage extends ConsumerWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final me = ref.watch(currentUserProvider);
    final value = ref.watch(membersProvider);

    return PageScaffold(
      title: 'Team members',
      maxWidth: 760,
      floatingActionButton: me.isOwner
          ? FloatingActionButton.extended(onPressed: () => _add(context, ref), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Add member'))
          : null,
      body: AsyncBody<List<Member>>(
        value: value,
        onRetry: () => ref.invalidate(membersProvider),
        builder: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            for (final m in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: m.isOwner || m.userId == me.userId ? null : () => _manage(context, ref, m, me),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Avatar(m.name, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name + (m.userId == me.userId ? '  (you)' : ''), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            Text([if (m.email != null) m.email!, if (m.employeeCode != null) m.employeeCode!].join('  |  '), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusPill(roleLabel(m.role), tone: m.isOwner ? Tone.brand : Tone.info, dense: true),
                          if (!m.isActive) const Padding(padding: EdgeInsets.only(top: 4), child: StatusPill('Deactivated', tone: Tone.danger, dense: true)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text('Team members sign in with their own email and password. Deactivating a member blocks their access immediately.', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var role = 'cashier';
    var saving = false;
    String? error;
    await showAppSheet<void>(
      context,
      title: 'Add team member',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(controller: name, label: 'Full name', validator: Validators.required('Name'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 14),
              AppTextField(controller: email, label: 'Email', keyboardType: TextInputType.emailAddress, validator: Validators.email),
              const SizedBox(height: 14),
              AppTextField(controller: phone, label: 'Phone (optional)', keyboardType: TextInputType.phone, validator: Validators.optionalPhone),
              const SizedBox(height: 14),
              PickerField<String>(
                label: 'Role',
                value: role,
                options: const [
                  PickerOption('manager', 'Manager', subtitle: 'Runs sales, purchases, stock and reports'),
                  PickerOption('cashier', 'Cashier', subtitle: 'Sells at the counter and collects dues'),
                  PickerOption('storekeeper', 'Storekeeper', subtitle: 'Receives goods and manages stock'),
                ],
                onChanged: (v) => setState(() => role = v ?? role),
              ),
              const SizedBox(height: 14),
              AppTextField(controller: password, label: 'Temporary password', obscure: true, validator: Validators.password, helper: 'At least 8 characters. Share it with the team member.'),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: ctx.colors.danger, fontWeight: FontWeight.w700))),
              const SizedBox(height: 18),
              AppButton('Create account', expand: true, loading: saving, onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() {
                  saving = true;
                  error = null;
                });
                try {
                  await ref.read(settingsRepoProvider).createStaff(
                        email: email.text.trim(),
                        password: password.text,
                        fullName: name.text.trim(),
                        role: role,
                        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                      );
                  ref.invalidate(membersProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) showToast(context, '${name.text.trim()} added as ${roleLabel(role)}');
                } catch (e) {
                  setState(() {
                    saving = false;
                    error = friendlyError(e);
                  });
                }
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manage(BuildContext context, WidgetRef ref, Member m, AppUser me) async {
    await showAppSheet<void>(
      context,
      title: m.name,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('Role', roleLabel(m.role)),
          InfoRow('Email', m.email ?? '-'),
          InfoRow('Employee ID', m.employeeCode ?? '-'),
          InfoRow('Joined', Fmt.date(m.joinedOn)),
          const SizedBox(height: 16),
          PickerField<String>(
            label: 'Change role',
            value: m.role,
            options: const [PickerOption('manager', 'Manager'), PickerOption('cashier', 'Cashier'), PickerOption('storekeeper', 'Storekeeper')],
            onChanged: (v) async {
              if (v == null || v == m.role) return;
              Navigator.pop(ctx);
              try {
                await ref.read(settingsRepoProvider).updateMember(m.id, {'role': v});
                ref.invalidate(membersProvider);
                if (context.mounted) showToast(context, 'Role updated');
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (me.isOwner)
                AppButton('Reset password', icon: Icons.lock_reset_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () async {
                  Navigator.pop(ctx);
                  await _resetPassword(context, ref, m);
                }),
              AppButton(m.isActive ? 'Deactivate' : 'Activate', icon: m.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                  kind: m.isActive ? ButtonKind.danger : ButtonKind.primary, dense: true, onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(settingsRepoProvider).updateMember(m.id, {'is_active': !m.isActive});
                  ref.invalidate(membersProvider);
                  if (context.mounted) showToast(context, m.isActive ? '${m.name} deactivated' : '${m.name} activated');
                } catch (e) {
                  if (context.mounted) showToast(context, friendlyError(e), error: true);
                }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(BuildContext context, WidgetRef ref, Member m) async {
    final pw = TextEditingController();
    final ok = await showAppSheet<bool>(
      context,
      title: 'Reset password',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(controller: pw, label: 'New password for ${m.name}', obscure: true, autofocus: true),
          const SizedBox(height: 18),
          AppButton('Set password', expand: true, onPressed: () {
            if (pw.text.length < 8) return;
            Navigator.pop(ctx, true);
          }),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(settingsRepoProvider).resetPassword(m.id, pw.text);
        if (context.mounted) showToast(context, 'Password updated');
      } catch (e) {
        if (context.mounted) showToast(context, friendlyError(e), error: true);
      }
    }
  }
}

class RolesPage extends ConsumerStatefulWidget {
  const RolesPage({super.key});

  @override
  ConsumerState<RolesPage> createState() => _RolesPageState();
}

class _RolesPageState extends ConsumerState<RolesPage> {
  String _role = 'cashier';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final perms = ref.watch(rolePermissionsProvider(_role));
    return PageScaffold(
      title: 'Roles and permissions',
      maxWidth: 760,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'manager', label: Text('Manager')), ButtonSegment(value: 'cashier', label: Text('Cashier')), ButtonSegment(value: 'storekeeper', label: Text('Storekeeper'))],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 8),
          Text('The owner always has full access. Changes apply the next time the person opens the app.', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
          AsyncBody<Set<String>>(
            value: perms,
            onRetry: () => ref.invalidate(rolePermissionsProvider),
            loading: const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator())),
            builder: (granted) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in Perm.groups.entries) ...[
                  SectionHeader(group.key, padding: const EdgeInsets.only(top: 18, bottom: 8)),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < group.value.length; i++) ...[
                          if (i > 0) Divider(color: c.border, height: 1),
                          SwitchListTile(
                            title: Text(group.value[i].$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                            value: granted.contains(group.value[i].$1),
                            onChanged: (v) async {
                              try {
                                await ref.read(settingsRepoProvider).setPermission(_role, group.value[i].$1, v);
                                ref.invalidate(rolePermissionsProvider);
                              } catch (e) {
                                if (context.mounted) showToast(context, friendlyError(e), error: true);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
