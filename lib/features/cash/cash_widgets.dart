import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import 'cash_data.dart';

const kNotes = [1000, 500, 200, 100, 50, 20, 10, 5, 2, 1];

typedef CashCount = ({double total, Map<String, int> notes});

/// Counting helper: type how many notes and coins of each kind, or just the total.
Future<CashCount?> showCashCount(BuildContext context, {double? expected}) {
  return showAppSheet<CashCount>(context, title: 'Count the cash', maxWidth: 480, builder: (_) => _CashCountBody(expected: expected));
}

class _CashCountBody extends StatefulWidget {
  const _CashCountBody({this.expected});

  final double? expected;

  @override
  State<_CashCountBody> createState() => _CashCountBodyState();
}

class _CashCountBodyState extends State<_CashCountBody> {
  final Map<int, TextEditingController> _c = {for (final n in kNotes) n: TextEditingController()};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total => _c.entries.fold(0.0, (s, e) => s + e.key * (int.tryParse(e.value.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in kNotes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 90, child: Text(Fmt.money(n), style: const TextStyle(fontWeight: FontWeight.w800))),
                const Text('x'),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _c[n],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(isDense: true, hintText: '0'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(width: 96, child: Text(Fmt.money(n * (int.tryParse(_c[n]!.text) ?? 0)), textAlign: TextAlign.right)),
              ],
            ),
          ),
        const Divider(),
        Row(
          children: [
            const Text('Total counted', style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(Fmt.money(_total), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        if (widget.expected != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              (_total - widget.expected!).abs() < 0.005 ? 'Matches the system' : 'Difference ${Fmt.money(_total - widget.expected!)}',
              style: TextStyle(color: (_total - widget.expected!).abs() < 0.005 ? col.success : col.warning, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 14),
        AppButton('Use this count', expand: true, onPressed: () {
          Navigator.pop(context, (total: _total, notes: {for (final e in _c.entries) if ((int.tryParse(e.value.text) ?? 0) > 0) '${e.key}': int.parse(e.value.text)}));
        }),
      ],
    );
  }
}

/// Deposit, withdrawal or transfer. [cashOnly] limits the accounts to cash (used by cashiers at the register).
Future<bool?> showAccountEntrySheet(
  BuildContext context, {
  required String entryType,
  required List<AccountBalance> accounts,
  String? accountId,
  bool cashOnly = false,
}) {
  final title = switch (entryType) {
    'deposit' => cashOnly ? 'Cash in' : 'Deposit',
    'withdrawal' => cashOnly ? 'Cash out' : 'Withdrawal',
    _ => 'Transfer between accounts',
  };
  return showAppSheet<bool>(
    context,
    title: title,
    maxWidth: 480,
    builder: (_) => _EntryBody(entryType: entryType, accounts: cashOnly ? accounts.where((a) => a.isCash).toList() : accounts, accountId: accountId, cashOnly: cashOnly),
  );
}

class _EntryBody extends ConsumerStatefulWidget {
  const _EntryBody({required this.entryType, required this.accounts, this.accountId, required this.cashOnly});

  final String entryType;
  final List<AccountBalance> accounts;
  final String? accountId;
  final bool cashOnly;

  @override
  ConsumerState<_EntryBody> createState() => _EntryBodyState();
}

class _EntryBodyState extends ConsumerState<_EntryBody> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _ref = TextEditingController();
  String? _from;
  String? _to;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _from = widget.accountId ?? (widget.accounts.isEmpty ? null : widget.accounts.first.id);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = Fmt.parse(_amount.text);
    if (amount <= 0) return setState(() => _error = 'Enter an amount.');
    if (_from == null) return setState(() => _error = 'Choose an account.');
    if (widget.entryType == 'transfer' && _to == null) return setState(() => _error = 'Choose the account to transfer to.');
    if (widget.entryType != 'transfer' && _note.text.trim().isEmpty) return setState(() => _error = 'Write a short note.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(cashRepoProvider).entry({
        'account_id': _from,
        'entry_type': widget.entryType,
        'amount': amount,
        'to_account_id': widget.entryType == 'transfer' ? _to : null,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'reference': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      });
      refreshAfterTransaction(ref);
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
    final c = context.colors;
    final opts = [for (final a in widget.accounts) PickerOption(a.id, a.name, subtitle: Fmt.money(a.balance))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerField<String>(
          label: widget.entryType == 'transfer' ? 'From' : 'Account',
          value: _from,
          options: opts,
          onChanged: (v) => setState(() => _from = v),
          enabled: widget.accountId == null || widget.entryType == 'transfer',
        ),
        if (widget.entryType == 'transfer') ...[
          const SizedBox(height: 14),
          PickerField<String>(label: 'To', value: _to, options: [for (final o in opts) if (o.value != _from) o], onChanged: (v) => setState(() => _to = v)),
        ],
        const SizedBox(height: 14),
        MoneyField(controller: _amount, label: 'Amount', autofocus: true),
        const SizedBox(height: 14),
        FieldRow([
          AppTextField(controller: _note, label: widget.entryType == 'transfer' ? 'Note (optional)' : 'Note', hint: widget.entryType == 'withdrawal' ? 'Why is the money leaving?' : ''),
          AppTextField(controller: _ref, label: 'Reference (optional)', hint: 'Slip or transaction number'),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        AppButton('Save', expand: true, loading: _saving, onPressed: _save),
      ],
    );
  }
}
