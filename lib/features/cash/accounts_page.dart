import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/models/app_user.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/date_range_bar.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'cash_data.dart';
import 'cash_widgets.dart';

/// Cash, bank and mobile banking balances with deposit, withdrawal and transfer.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(accountBalancesProvider);
    final manage = user.can(Perm.accountsManage);
    final c = context.colors;

    Future<void> entry(String type, List<AccountBalance> accounts, {String? accountId}) async {
      final ok = await showAccountEntrySheet(context, entryType: type, accounts: accounts, accountId: accountId);
      if (ok == true) {
        ref.invalidate(accountBalancesProvider);
        if (context.mounted) showToast(context, 'Saved');
      }
    }

    return PageScaffold(
      title: 'Accounts',
      subtitle: 'Cash, bank and mobile banking',
      maxWidth: 820,
      body: AsyncBody<List<AccountBalance>>(
        value: value,
        onRetry: () => ref.invalidate(accountBalancesProvider),
        builder: (accounts) {
          final total = accounts.fold<double>(0, (s, a) => s + a.balance);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            children: [
              AppCard(
                color: c.primarySoft,
                borderColor: Colors.transparent,
                child: Row(
                  children: [
                    Expanded(child: Text('Total across accounts', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                    MoneyText(total, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (manage) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton('Deposit', icon: Icons.south_west_rounded, dense: true, onPressed: () => entry('deposit', accounts)),
                    AppButton('Withdraw', icon: Icons.north_east_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => entry('withdrawal', accounts)),
                    AppButton('Transfer', icon: Icons.swap_horiz_rounded, kind: ButtonKind.secondary, dense: true, onPressed: () => entry('transfer', accounts)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              for (final a in accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: user.can(Perm.accountsView) ? () => context.push('/cash/accounts/${a.id}') : null,
                    child: Row(
                      children: [
                        IconBadge(a.isCash ? Icons.payments_outlined : (a.type == 'bank' ? Icons.account_balance_outlined : Icons.smartphone_rounded), tone: a.isCash ? Tone.success : Tone.info, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              if ((a.accountNo ?? '').isNotEmpty) Text(a.accountNo!, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                            ],
                          ),
                        ),
                        MoneyText(a.balance, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: a.balance < 0 ? c.danger : c.text)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AccountStatementPage extends ConsumerStatefulWidget {
  const AccountStatementPage({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<AccountStatementPage> createState() => _AccountStatementPageState();
}

class _AccountStatementPageState extends ConsumerState<AccountStatementPage> {
  DateRange _range = DateRange.of(RangePreset.thisMonth);

  PrintableDoc _doc(Statement s) => PrintableDoc(
        title: 'Account statement',
        number: s.name,
        date: DateTime.now(),
        partyLabel: 'Period',
        partyName: '${Fmt.date(_range.from)} to ${Fmt.date(_range.to)}',
        simple: true,
        lines: [
          for (final r in s.rows)
            PrintLine(name: '${Fmt.dateTime(r.date)}  ${r.description}', qty: '', price: 0, total: r.direction == 'in' ? r.amount : -r.amount),
        ],
        totals: [
          ('Opening balance', Fmt.pdfMoney(s.opening), false),
          ('Money in', Fmt.pdfMoney(s.totalIn), false),
          ('Money out', Fmt.pdfMoney(s.totalOut), false),
          ('Closing balance', Fmt.pdfMoney(s.closing), true),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final value = ref.watch(statementProvider((accountId: widget.accountId, from: _range.from, to: _range.to)));
    return PageScaffold(
      title: value.valueOrNull?.name ?? 'Statement',
      maxWidth: 820,
      actions: [
        if (value.hasValue)
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              try {
                await PdfBuilder.printDoc(_doc(value.value!), user.business, paper: PaperSize.a4);
              } catch (e) {
                if (context.mounted) showToast(context, friendlyError(e), error: true);
              }
            },
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          DateRangeBar(
            value: _range,
            onChanged: (r) => setState(() => _range = r),
            presets: const [RangePreset.today, RangePreset.last7, RangePreset.last30, RangePreset.thisMonth, RangePreset.custom],
          ),
          const SizedBox(height: 12),
          AsyncBody<Statement>(
            value: value,
            onRetry: () => ref.invalidate(statementProvider),
            builder: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    children: [
                      InfoRow('Opening balance', Fmt.money(s.opening)),
                      InfoRow('Money in', Fmt.money(s.totalIn), valueColor: c.success),
                      InfoRow('Money out', Fmt.money(s.totalOut), valueColor: c.danger),
                      InfoRow('Closing balance', Fmt.money(s.closing), bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (s.rows.isEmpty)
                  const EmptyState(icon: Icons.receipt_long_outlined, title: 'No movements', message: 'Nothing was recorded in this period.')
                else
                  for (final r in s.rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: IconBadge(r.direction == 'in' ? Icons.south_west_rounded : Icons.north_east_rounded, tone: r.direction == 'in' ? Tone.success : Tone.danger, size: 38),
                      title: Text(r.description.isEmpty ? (sourceLabels[r.source] ?? r.source) : r.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${Fmt.dateTime(r.date)}  |  balance ${Fmt.money(r.balance)}'),
                      trailing: Text('${r.direction == 'in' ? '+' : '-'}${Fmt.money(r.amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: r.direction == 'in' ? c.success : c.danger)),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
