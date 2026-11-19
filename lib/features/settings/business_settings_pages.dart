import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/common_data.dart';
import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/json.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';
import 'settings_data.dart';

// ------------------------------------------------------------------ business profile
class BusinessProfilePage extends ConsumerStatefulWidget {
  const BusinessProfilePage({super.key});

  @override
  ConsumerState<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends ConsumerState<BusinessProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final _b = ref.read(currentUserProvider).business;
  late final _name = TextEditingController(text: _b.name);
  late final _address = TextEditingController(text: _b.address ?? '');
  late final _phone = TextEditingController(text: _b.phone ?? '');
  late final _email = TextEditingController(text: _b.email ?? '');
  late final _website = TextEditingController(text: _b.website ?? '');
  String? _logoUrl;
  Uint8List? _newLogo;
  String _logoExt = 'png';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _logoUrl = _b.logoUrl;
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email, _website]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final dot = file.name.lastIndexOf('.');
    setState(() {
      _newLogo = bytes;
      _logoExt = dot >= 0 ? file.name.substring(dot + 1).toLowerCase() : 'png';
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(_logoExt)) _logoExt = 'png';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(settingsRepoProvider);
      var logo = _logoUrl;
      if (_newLogo != null) logo = await repo.uploadLogo(_newLogo!, _logoExt);
      await repo.updateBusiness({
        'name': _name.text.trim(),
        'address': nonEmpty(_address.text),
        'phone': nonEmpty(_phone.text),
        'email': nonEmpty(_email.text),
        'website': nonEmpty(_website.text),
        'logo_url': logo,
      });
      ref.invalidate(appUserProvider);
      if (mounted) {
        context.pop();
        showToast(context, 'Business profile saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormScaffold(
      title: 'Business profile',
      formKey: _formKey,
      saving: _saving,
      onSave: _save,
      children: [
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _pickLogo,
            child: Container(
              width: 104,
              height: 104,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(28), border: Border.all(color: c.border)),
              child: _newLogo != null
                  ? Image.memory(_newLogo!, fit: BoxFit.cover)
                  : (_logoUrl ?? '').isNotEmpty
                      ? Image.network(_logoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.storefront_outlined))
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, color: c.textMuted), const SizedBox(height: 4), Text('Logo', style: TextStyle(color: c.textMuted, fontSize: 12))]),
            ),
          ),
        ),
        FormSection('Business', children: [
          AppTextField(controller: _name, label: 'Business name', validator: Validators.required('Business name'), textCapitalization: TextCapitalization.words),
          AppTextField(controller: _address, label: 'Address', maxLines: 2),
          FieldRow([
            AppTextField(controller: _phone, label: 'Phone', keyboardType: TextInputType.phone, validator: Validators.optionalPhone),
            AppTextField(controller: _email, label: 'Email', keyboardType: TextInputType.emailAddress, validator: Validators.optionalEmail),
          ]),
          AppTextField(controller: _website, label: 'Website', keyboardType: TextInputType.url),
        ]),
        FormSection('Regional', children: [
          InfoRow('Currency', 'Bangladeshi Taka (BDT)'),
          InfoRow('Time zone', ref.read(currentUserProvider).business.timezone),
          InfoRow('Language', 'English'),
        ]),
      ],
    );
  }
}

// ------------------------------------------------------------------ sales rules
class SalesSettingsPage extends ConsumerStatefulWidget {
  const SalesSettingsPage({super.key});

  @override
  ConsumerState<SalesSettingsPage> createState() => _SalesSettingsPageState();
}

class _SalesSettingsPageState extends ConsumerState<SalesSettingsPage> {
  late final _b = ref.read(currentUserProvider).business;
  late final _invoicePrefix = TextEditingController(text: _b.invoicePrefix);
  late final _purchasePrefix = TextEditingController(text: _b.purchasePrefix);
  late final _defaultTax = TextEditingController(text: ((_b.settings['default_tax_rate'] as num?) ?? 0) == 0 ? '' : Fmt.qty(_b.settings['default_tax_rate'] as num));
  late bool _negative = _b.allowNegativeStock;
  late bool _due = _b.allowDueSale;
  late bool _customerRequired = _b.customerRequired;
  bool _saving = false;

  @override
  void dispose() {
    _invoicePrefix.dispose();
    _purchasePrefix.dispose();
    _defaultTax.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepoProvider).saveSettings(_b, {
        'invoice_prefix': _invoicePrefix.text.trim().isEmpty ? 'INV' : _invoicePrefix.text.trim().toUpperCase(),
        'purchase_prefix': _purchasePrefix.text.trim().isEmpty ? 'PUR' : _purchasePrefix.text.trim().toUpperCase(),
        'default_tax_rate': Fmt.parse(_defaultTax.text),
        'allow_negative_stock': _negative,
        'allow_due_sale': _due,
        'customer_required': _customerRequired,
      });
      ref.invalidate(appUserProvider);
      if (mounted) {
        context.pop();
        showToast(context, 'Settings saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: 'Sales and stock rules',
      saving: _saving,
      onSave: _save,
      children: [
        FormSection('Numbering', subtitle: 'Prefixes apply to new documents. Existing numbers do not change.', children: [
          FieldRow([
            AppTextField(controller: _invoicePrefix, label: 'Invoice prefix', hint: 'INV', textCapitalization: TextCapitalization.characters),
            AppTextField(controller: _purchasePrefix, label: 'Purchase prefix', hint: 'PUR', textCapitalization: TextCapitalization.characters),
          ]),
        ]),
        FormSection('Rules', children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow credit (due) sales', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Customers can take goods and pay later.'),
            value: _due,
            onChanged: (v) => setState(() => _due = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Require a customer on every sale', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Walk-in sales are blocked.'),
            value: _customerRequired,
            onChanged: (v) => setState(() => _customerRequired = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow selling below zero stock', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Not recommended. Stock counts can become negative.'),
            value: _negative,
            onChanged: (v) => setState(() => _negative = v),
          ),
        ]),
        FormSection('Tax', children: [
          AppTextField(
            controller: _defaultTax,
            label: 'Default VAT / tax rate for new products (%)',
            hint: '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ]),
      ],
    );
  }
}

// ------------------------------------------------------------------ receipt and printer
class ReceiptSettingsPage extends ConsumerStatefulWidget {
  const ReceiptSettingsPage({super.key});

  @override
  ConsumerState<ReceiptSettingsPage> createState() => _ReceiptSettingsPageState();
}

class _ReceiptSettingsPageState extends ConsumerState<ReceiptSettingsPage> {
  late final _b = ref.read(currentUserProvider).business;
  late final _footer = TextEditingController(text: _b.invoiceFooter);
  late final _terms = TextEditingController(text: _b.invoiceTerms);
  late String _paper = _b.paperSize;
  late bool _autoPrint = _b.autoPrint;
  bool _saving = false;

  @override
  void dispose() {
    _footer.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepoProvider).saveSettings(_b, {
        'paper_size': _paper,
        'auto_print': _autoPrint,
        'invoice_footer': _footer.text.trim(),
        'invoice_terms': _terms.text.trim(),
      });
      ref.invalidate(appUserProvider);
      if (mounted) {
        context.pop();
        showToast(context, 'Receipt settings saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FormScaffold(
      title: 'Receipt and printer',
      saving: _saving,
      onSave: _save,
      children: [
        FormSection('Paper', children: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: '58mm', label: Text('58 mm')), ButtonSegment(value: '80mm', label: Text('80 mm')), ButtonSegment(value: 'A4', label: Text('A4'))],
            selected: {_paper == 'a4' ? 'A4' : _paper},
            onSelectionChanged: (s) => setState(() => _paper = s.first),
          ),
          Text('Thermal printers connected to your phone, tablet or computer work through the system print dialog. Pick the 58 mm or 80 mm paper that matches your roll.',
              style: context.text.bodySmall?.copyWith(color: c.textMuted)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Open the print dialog after every sale', style: TextStyle(fontWeight: FontWeight.w700)),
            value: _autoPrint,
            onChanged: (v) => setState(() => _autoPrint = v),
          ),
        ]),
        FormSection('Text on the invoice', children: [
          AppTextField(controller: _footer, label: 'Footer message', maxLines: 2),
          AppTextField(controller: _terms, label: 'Terms and conditions', maxLines: 4, hint: 'e.g. Goods once sold are not returnable without the invoice.'),
        ]),
      ],
    );
  }
}

// ------------------------------------------------------------------ payment methods
class PaymentMethodsPage extends ConsumerWidget {
  const PaymentMethodsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(paymentAccountsProvider);

    Future<void> edit([PaymentAccount? existing]) async {
      final name = TextEditingController(text: existing?.name ?? '');
      final number = TextEditingController(text: existing?.accountNo ?? '');
      final opening = TextEditingController();
      var type = existing?.type ?? 'mfs';
      var active = existing?.isActive ?? true;
      final saved = await showAppSheet<bool>(
        context,
        title: existing == null ? 'New payment method' : 'Edit payment method',
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(controller: name, label: 'Name', hint: 'e.g. City Bank', autofocus: true),
              const SizedBox(height: 14),
              PickerField<String>(
                label: 'Type',
                value: type,
                options: const [
                  PickerOption('cash', 'Cash'),
                  PickerOption('mfs', 'Mobile banking'),
                  PickerOption('bank', 'Bank account'),
                  PickerOption('card', 'Card'),
                  PickerOption('other', 'Other'),
                ],
                onChanged: (v) => setState(() => type = v ?? type),
              ),
              const SizedBox(height: 14),
              AppTextField(controller: number, label: 'Account or wallet number (optional)', keyboardType: TextInputType.number),
              if (existing == null) ...[const SizedBox(height: 14), MoneyField(controller: opening, label: 'Opening balance')],
              if (existing != null)
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v) => setState(() => active = v)),
              const SizedBox(height: 18),
              AppButton('Save', expand: true, onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              }),
            ],
          ),
        ),
      );
      if (saved == true && context.mounted) {
        try {
          await ref.read(catalogRepoProvider).savePaymentAccount(
                id: existing?.id,
                name: name.text,
                type: type,
                accountNo: number.text,
                openingBalance: Fmt.parse(opening.text),
                isActive: active,
              );
          ref.invalidate(paymentAccountsProvider);
          if (context.mounted) showToast(context, 'Payment method saved');
        } catch (e) {
          if (context.mounted) showToast(context, friendlyError(e), error: true);
        }
      }
    }

    return PageScaffold(
      title: 'Payment methods',
      maxWidth: 760,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.add_rounded), label: const Text('Add')),
      body: AsyncBody<List<PaymentAccount>>(
        value: value,
        onRetry: () => ref.invalidate(paymentAccountsProvider),
        builder: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => edit(a),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      IconBadge(switch (a.type) { 'cash' => Icons.payments_outlined, 'bank' => Icons.account_balance_outlined, 'card' => Icons.credit_card_rounded, 'mfs' => Icons.phone_android_rounded, _ => Icons.wallet_outlined },
                          tone: a.isActive ? Tone.brand : Tone.neutral, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            Text([if (a.accountNo != null) a.accountNo!, if (!a.isActive) 'Inactive'].join('  |  ').isEmpty ? 'Balance from recorded transactions' : [if (a.accountNo != null) a.accountNo!, if (!a.isActive) 'Inactive'].join('  |  '),
                                style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                          ],
                        ),
                      ),
                      MoneyText(a.balance, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: a.balance < 0 ? c.danger : null)),
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
