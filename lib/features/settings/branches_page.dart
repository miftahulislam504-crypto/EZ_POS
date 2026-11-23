import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../cash/cash_data.dart';
import '../inventory/tracking_data.dart';

/// Branches, warehouses and cash counters. Per-branch POS, price and user restrictions arrive with Phase 3.
class BranchesPage extends ConsumerWidget {
  const BranchesPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {BranchOption? branch}) async {
    final ok = await showAppSheet<bool>(context, title: branch == null ? 'Add location' : 'Edit location', builder: (_) => _BranchForm(branch: branch));
    if (ok == true) ref.invalidate(branchesProvider);
  }

  Future<void> _counter(BuildContext context, WidgetRef ref, BranchOption branch, {RegisterRow? register}) async {
    final ok = await showAppSheet<bool>(context, title: register == null ? 'Add counter' : 'Edit counter', builder: (_) => _CounterForm(branchId: branch.id, register: register));
    if (ok == true) ref.invalidate(registersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final branches = ref.watch(branchesProvider);
    final registers = ref.watch(registersProvider).valueOrNull ?? const <RegisterRow>[];
    return PageScaffold(
      title: 'Branches and counters',
      maxWidth: 760,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('Add location')),
      body: AsyncBody<List<BranchOption>>(
        value: branches,
        onRetry: () => ref.invalidate(branchesProvider),
        builder: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            for (final b in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconBadge(b.isWarehouse ? Icons.warehouse_outlined : Icons.storefront_outlined, tone: b.isActive ? Tone.brand : Tone.neutral, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text([b.isWarehouse ? 'Warehouse' : 'Branch', if (b.isDefault) 'Main', if (!b.isActive) 'Inactive', if ((b.address ?? '').isNotEmpty) b.address!].join('  |  '), style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, ref, branch: b)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final r in registers.where((r) => r.branchId == b.id))
                            ActionChip(label: Text(r.isActive ? r.name : '${r.name} (off)'), onPressed: () => _counter(context, ref, b, register: r)),
                          ActionChip(avatar: const Icon(Icons.add_rounded, size: 16), label: const Text('Counter'), onPressed: () => _counter(context, ref, b)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchForm extends ConsumerStatefulWidget {
  const _BranchForm({this.branch});

  final BranchOption? branch;

  @override
  ConsumerState<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends ConsumerState<_BranchForm> {
  late final _name = TextEditingController(text: widget.branch?.name);
  late final _address = TextEditingController(text: widget.branch?.address);
  late final _phone = TextEditingController(text: widget.branch?.phone);
  late String _kind = widget.branch?.kind ?? 'branch';
  late bool _active = widget.branch?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter a name.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(trackingRepoProvider).saveBranch({
        'id': widget.branch?.id,
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'kind': _kind,
        'is_active': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(controller: _name, label: 'Name', textCapitalization: TextCapitalization.words, autofocus: true),
        const SizedBox(height: 14),
        PickerField<String>(
          label: 'Type',
          value: _kind,
          options: const [PickerOption('branch', 'Branch (sells to customers)'), PickerOption('warehouse', 'Warehouse (stores stock)')],
          onChanged: (v) => setState(() => _kind = v ?? 'branch'),
        ),
        const SizedBox(height: 14),
        AppTextField(controller: _address, label: 'Address', maxLines: 2),
        const SizedBox(height: 14),
        AppTextField(controller: _phone, label: 'Phone', keyboardType: TextInputType.phone),
        if (widget.branch != null && !(widget.branch!.isDefault))
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w700))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        AppButton('Save', expand: true, loading: _saving, onPressed: _save),
      ],
    );
  }
}

class _CounterForm extends ConsumerStatefulWidget {
  const _CounterForm({required this.branchId, this.register});

  final String branchId;
  final RegisterRow? register;

  @override
  ConsumerState<_CounterForm> createState() => _CounterFormState();
}

class _CounterFormState extends ConsumerState<_CounterForm> {
  late final _name = TextEditingController(text: widget.register?.name);
  late bool _active = widget.register?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter a counter name.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(cashRepoProvider).saveRegister({'id': widget.register?.id, 'branch_id': widget.branchId, 'name': _name.text.trim(), 'is_active': _active});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(controller: _name, label: 'Counter name', hint: 'Counter 2', autofocus: true),
        if (widget.register != null)
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w700))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.colors.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        AppButton('Save', expand: true, loading: _saving, onPressed: _save),
      ],
    );
  }
}
