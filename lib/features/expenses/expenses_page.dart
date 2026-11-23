import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/data/refresh.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/attachments_section.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/date_range_bar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/security/password_confirm.dart';
import 'expenses_data.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  DateRange _range = DateRange.of(RangePreset.thisMonth);
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final cats = ref.watch(expenseCategoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    final value = ref.watch(expensesProvider((range: _range, categoryId: _categoryId)));

    return PageScaffold(
      title: 'Expenses',
      maxWidth: 900,
      floatingActionButton: user.can(Perm.expensesCreate)
          ? FloatingActionButton.extended(onPressed: () => showExpenseSheet(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('Add expense'))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: DateRangeBar(value: _range, onChanged: (r) => setState(() => _range = r), presets: const [
              RangePreset.today, RangePreset.last7, RangePreset.thisMonth, RangePreset.last30, RangePreset.custom,
            ]),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('All categories'), selected: _categoryId == null, onSelected: (_) => setState(() => _categoryId = null))),
                for (final cat in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(cat.name), selected: _categoryId == cat.id, onSelected: (_) => setState(() => _categoryId = _categoryId == cat.id ? null : cat.id)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<ExpenseSummary>(
              value: value,
              onRetry: () => ref.invalidate(expensesProvider),
              builder: (s) {
                if (s.rows.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_outlined,
                    title: 'No expenses in this period',
                    message: 'Record rent, bills, salaries and other running costs.',
                    actionLabel: user.can(Perm.expensesCreate) ? 'Add expense' : null,
                    onAction: () => showExpenseSheet(context, ref),
                  );
                }
                final byCat = s.byCategory;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total expenses', style: context.text.labelLarge?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          MoneyText(s.total, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          if (byCat.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            for (final e in byCat.entries.take(5))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(flex: 3, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    Expanded(
                                      flex: 4,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(value: s.total == 0 ? 0 : e.value / s.total, minHeight: 8, backgroundColor: c.surfaceMuted),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(width: 92, child: Text(Fmt.money(e.value), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final e in s.rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          onTap: () => _details(context, e, user),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              IconBadge(e.isVoid ? Icons.block_rounded : Icons.receipt_outlined, tone: e.isVoid ? Tone.neutral : Tone.warning, size: 42),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                    Text('${e.categoryName ?? 'Uncategorised'}  |  ${Fmt.date(e.date)}', style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  MoneyText(e.amount, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, decoration: e.isVoid ? TextDecoration.lineThrough : null)),
                                  if (e.isVoid) const StatusPill('Void', dense: true) else if (e.isRecurring) StatusPill(e.recurrence ?? 'Recurring', tone: Tone.info, dense: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _details(BuildContext context, ExpenseRow e, AppUser user) {
    showAppSheet<void>(
      context,
      title: e.title,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('Amount', Fmt.money(e.amount), bold: true),
          InfoRow('Category', e.categoryName ?? '-'),
          InfoRow('Date', Fmt.date(e.date)),
          InfoRow('Paid from', e.accountName ?? '-'),
          if (e.paidBy != null) InfoRow('Paid by', e.paidBy!),
          if (e.note != null) InfoRow('Note', e.note!),
          if (e.isVoid) InfoRow('Void reason', e.voidReason ?? '-', valueColor: ctx.colors.danger),
          const SizedBox(height: 8),
          AttachmentsSection(
            entityType: 'expense',
            entityId: e.id,
            title: 'Receipt',
            canEdit: !e.isVoid && user.can(Perm.expensesCreate),
            canDelete: !e.isVoid && user.can(Perm.expensesCreate),
          ),
          if (!e.isVoid && user.can(Perm.expensesVoid)) ...[
            const SizedBox(height: 16),
            AppButton('Void expense', kind: ButtonKind.danger, icon: Icons.block_rounded, onPressed: () async {
              Navigator.pop(ctx);
              final reason = await reasonDialog(context, title: 'Void this expense?', message: 'The money will be returned to the account it was paid from.', confirmLabel: 'Void expense');
              if (reason == null || !context.mounted) return;
              if (!await confirmSensitive(context, ref)) return;
              try {
                await ref.read(expenseRepoProvider).voidExpense(e.id, reason);
                refreshAfterTransaction(ref);
                if (context.mounted) showToast(context, 'Expense voided');
              } catch (err) {
                if (context.mounted) showToast(context, friendlyError(err), error: true);
              }
            }),
          ],
        ],
      ),
    );
  }
}

Future<void> showExpenseSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(context, title: 'Add expense', builder: (_) => const _ExpenseForm());
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm();

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _paidBy = TextEditingController();
  final _note = TextEditingController();
  String? _categoryId;
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _recurring = false;
  String _recurrence = 'monthly';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _amount, _paidBy, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Enter an expense name');
      return;
    }
    if (Fmt.parse(_amount.text) <= 0) {
      setState(() => _error = 'Enter an amount greater than zero');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Choose how it was paid');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(expenseRepoProvider).create({
        'title': _title.text.trim(),
        'amount': Fmt.parse(_amount.text),
        'category_id': _categoryId,
        'account_id': _accountId,
        'expense_date': Fmt.iso(_date),
        'paid_by': _paidBy.text.trim(),
        'note': _note.text.trim(),
        'is_recurring': _recurring,
        'recurrence': _recurring ? _recurrence : null,
      });
      refreshAfterTransaction(ref);
      if (mounted) {
        Navigator.pop(context);
        showToast(context, 'Expense saved');
      }
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
    final cats = ref.watch(expenseCategoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    final accounts = (ref.watch(paymentAccountsProvider).valueOrNull ?? const <PaymentAccount>[]).where((a) => a.isActive).toList();
    if (_accountId == null && accounts.isNotEmpty) _accountId = accounts.firstWhere((a) => a.isCash, orElse: () => accounts.first).id;
    final me = ref.watch(currentUserProvider);
    if (_paidBy.text.isEmpty) _paidBy.text = me.fullName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(controller: _title, label: 'Expense name', hint: 'e.g. Shop rent, November', autofocus: true, textCapitalization: TextCapitalization.sentences),
        const SizedBox(height: 14),
        FieldRow([
          MoneyField(controller: _amount, label: 'Amount'),
          DateField(label: 'Date', value: _date, lastDate: DateTime.now(), onChanged: (d) => setState(() => _date = d ?? _date)),
        ]),
        const SizedBox(height: 14),
        FieldRow([
          PickerField<String>(
            label: 'Category',
            hint: 'Select category',
            value: _categoryId,
            allowClear: true,
            options: [for (final cat in cats) PickerOption(cat.id, cat.name)],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          PickerField<String>(
            label: 'Paid from',
            value: _accountId,
            options: [for (final a in accounts) PickerOption(a.id, a.name)],
            onChanged: (v) => setState(() => _accountId = v),
          ),
        ]),
        const SizedBox(height: 14),
        AppTextField(controller: _paidBy, label: 'Spent by'),
        const SizedBox(height: 14),
        AppTextField(controller: _note, label: 'Note (optional)', maxLines: 2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Recurring expense', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Marks regular costs like rent or internet.'),
          value: _recurring,
          onChanged: (v) => setState(() => _recurring = v),
        ),
        if (_recurring)
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'weekly', label: Text('Weekly')), ButtonSegment(value: 'monthly', label: Text('Monthly')), ButtonSegment(value: 'yearly', label: Text('Yearly'))],
            selected: {_recurrence},
            onSelectionChanged: (s) => setState(() => _recurrence = s.first),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
        const SizedBox(height: 18),
        AppButton('Save expense', expand: true, loading: _saving, onPressed: _save),
      ],
    );
  }
}
