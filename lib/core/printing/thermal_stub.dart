import 'printer_config.dart';

/// Used where direct printing is impossible (web). Receipts use the browser print dialog there.
bool get thermalSupported => false;

Set<PrinterLink> get availableLinks => const {};

String get thermalUnavailableReason =>
    'Direct printing needs the Android or iOS app. In the browser, receipts open the print dialog.';

Future<void> sendToPrinter(PrinterConfig config, List<int> bytes) =>
    Future.error(UnsupportedError('Direct printing is not available here.'));

Future<List<FoundPrinter>> discoverPrinters(PrinterLink link, {Duration timeout = const Duration(seconds: 6)}) async => const [];
