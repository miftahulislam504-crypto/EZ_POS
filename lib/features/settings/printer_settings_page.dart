import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/errors.dart';
import '../../core/printing/direct_printer.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/printing/printer_config.dart';
import '../../core/printing/thermal_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

/// Sets up the receipt printer for this device: Bluetooth, USB or network. Saved on the device only.
class PrinterSettingsPage extends ConsumerStatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  ConsumerState<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends ConsumerState<PrinterSettingsPage> {
  PrinterConfig _cfg = const PrinterConfig();
  bool _loaded = false;
  bool _scanning = false;
  bool _testing = false;
  bool _saving = false;
  List<FoundPrinter> _found = const [];
  String? _selectedKey;
  String? _error;
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '9100');
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    PrinterConfig.load().then((c) {
      if (!mounted) return;
      setState(() {
        _cfg = c;
        _ip.text = c.link == PrinterLink.network ? c.address : '';
        _port.text = '${c.port}';
        _name.text = c.link == PrinterLink.network ? c.name : '';
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _name.dispose();
    super.dispose();
  }

  void _setLink(PrinterLink l) {
    setState(() {
      _error = null;
      _found = const [];
      _selectedKey = null;
      _cfg = PrinterConfig(link: l, cutPaper: _cfg.cutPaper, openDrawer: _cfg.openDrawer, port: int.tryParse(_port.text) ?? 9100);
      if (l == PrinterLink.network) {
        _cfg = _cfg.copyWith(address: _ip.text.trim(), name: _name.text.trim());
      }
    });
  }

  /// The configuration the form currently describes.
  PrinterConfig get _current {
    if (_cfg.link == PrinterLink.network) {
      return _cfg.copyWith(address: _ip.text.trim(), name: _name.text.trim(), port: int.tryParse(_port.text.trim()) ?? 9100);
    }
    return _cfg;
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _found = const [];
    });
    try {
      final list = await discoverPrinters(_cfg.link);
      if (!mounted) return;
      setState(() {
        _found = list;
        _scanning = false;
        if (list.isEmpty) {
          _error = _cfg.link == PrinterLink.bluetooth
              ? 'No printers found. Switch the printer on, pair it in the phone Bluetooth settings, then scan again.'
              : 'No USB printers found. Connect the printer with a USB cable (OTG adapter on phones) and scan again.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  void _pick(FoundPrinter p) {
    _selectedKey = p.key;
    setState(() => _cfg = _cfg.copyWith(name: p.name, address: p.address ?? '', vendorId: p.vendorId, productId: p.productId, isBle: _cfg.link == PrinterLink.bluetooth && Theme.of(context).platform == TargetPlatform.iOS));
  }

  bool _valid(PrinterConfig c) {
    if (c.link == PrinterLink.none) return true;
    if (c.link == PrinterLink.network) {
      final ok = RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(c.address) && c.address.isNotEmpty;
      if (!ok) {
        setState(() => _error = 'Enter the printer IP address, for example 192.168.1.50.');
        return false;
      }
      if (c.port < 1 || c.port > 65535) {
        setState(() => _error = 'The port must be between 1 and 65535. Most printers use 9100.');
        return false;
      }
      return true;
    }
    if (!c.isConfigured) {
      setState(() => _error = 'Scan and choose a printer first.');
      return false;
    }
    return true;
  }

  Future<void> _test() async {
    final c = _current;
    if (c.link == PrinterLink.none || !_valid(c)) return;
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      final user = ref.read(currentUserProvider);
      final paper = paperFromSetting(user.business.paperSize);
      final roll = paper == PaperSize.a4 ? PaperSize.mm80 : paper;
      final doc = PrintableDoc(
        title: 'Test print',
        number: 'TEST-001',
        date: DateTime.now(),
        partyLabel: 'Printer',
        partyName: c.name.isEmpty ? printerLinkLabel(c.link) : c.name,
        lines: const [PrintLine(name: 'Sample item', qty: '1', price: 100, total: 100)],
        totals: const [('Total', 'BDT 100.00', true)],
        note: 'If you can read this, the printer is set up correctly.',
      );
      final pdf = await PdfBuilder.build(doc, user.business, paper: roll);
      await DirectPrinter.printTest(c, roll, pdf);
      if (mounted) showToast(context, 'Test receipt sent');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final c = _current;
    if (!_valid(c)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    await c.save();
    if (!mounted) return;
    context.pop();
    showToast(context, c.link == PrinterLink.none ? 'Printer removed from this device' : 'Printer saved on this device');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final paper = paperFromSetting(user.business.paperSize);
    if (!_loaded) return Scaffold(appBar: AppBar(title: const Text('Printer on this device')), body: const ListSkeleton(rows: 3));

    if (!thermalSupported) {
      return PageScaffold(
        title: 'Printer on this device',
        maxWidth: 640,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: c.info),
                  const SizedBox(width: 12),
                  Expanded(child: Text(thermalUnavailableReason, style: TextStyle(color: c.text))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final links = [PrinterLink.none, ...PrinterLink.values.where((l) => availableLinks.contains(l))];
    final cfg = _current;
    return FormScaffold(
      title: 'Printer on this device',
      saving: _saving,
      onSave: _save,
      saveLabel: 'Save',
      children: [
        FormSection('Connection', subtitle: 'The printer is remembered on this device only. Other devices set up their own.', children: [
          PickerField<PrinterLink>(
            label: 'Connect with',
            value: cfg.link,
            options: [for (final l in links) PickerOption(l, printerLinkLabel(l))],
            onChanged: (v) => _setLink(v ?? PrinterLink.none),
          ),
          if (cfg.link == PrinterLink.none)
            Text('Receipts open the system print dialog. Choose a connection to print straight to a thermal printer.', style: TextStyle(color: c.textMuted)),
          if (cfg.link == PrinterLink.network) ...[
            FieldRow([
              AppTextField(controller: _ip, label: 'Printer IP address', hint: '192.168.1.50', keyboardType: TextInputType.url),
              AppTextField(controller: _port, label: 'Port', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            ]),
            AppTextField(controller: _name, label: 'Name (optional)', hint: 'Counter printer'),
          ],
          if (cfg.link == PrinterLink.bluetooth || cfg.link == PrinterLink.usb) ...[
            AppButton(_scanning ? 'Scanning...' : 'Find printers', icon: Icons.search_rounded, kind: ButtonKind.secondary, loading: _scanning, onPressed: _scan),
            for (final p in _found)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name.isEmpty ? 'Unnamed printer' : p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p.address ?? [p.vendorId, p.productId].whereType<String>().join(' : ')),
                value: p.key,
                groupValue: _selectedKey,
                onChanged: (_) => _pick(p),
              ),
            if (cfg.isConfigured && _found.isEmpty)
              Text('Selected: ${cfg.summary}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ]),
        if (cfg.link != PrinterLink.none)
          FormSection('Receipt options', children: [
            InfoRow('Paper', paper == PaperSize.a4 ? 'A4 (set a 58 mm or 80 mm roll in Receipt and printer settings to print directly)' : (paper == PaperSize.mm58 ? '58 mm roll' : '80 mm roll')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cut paper after each receipt', style: TextStyle(fontWeight: FontWeight.w700)),
              value: cfg.cutPaper,
              onChanged: (v) => setState(() => _cfg = _current.copyWith(cutPaper: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open the cash drawer', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Sends the drawer pulse with each receipt. Needs a drawer connected to the printer.'),
              value: cfg.openDrawer,
              onChanged: (v) => setState(() => _cfg = _current.copyWith(openDrawer: v)),
            ),
            AppButton('Print test receipt', icon: Icons.print_outlined, kind: ButtonKind.secondary, loading: _testing, onPressed: _test),
          ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w700))),
      ],
    );
  }
}
