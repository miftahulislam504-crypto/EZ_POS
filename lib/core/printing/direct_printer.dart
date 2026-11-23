import 'dart:async';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../widgets/feedback.dart';
import 'escpos.dart';
import 'pdf_builder.dart';
import 'printer_config.dart';
import 'thermal_platform.dart';

/// Prints the same receipt layout the PDF builder makes straight to a thermal printer (Bluetooth, USB or network),
/// without the system print dialog.
class DirectPrinter {
  DirectPrinter._();

  /// Printable width in dots at 203 dpi: 48 mm on 58 mm paper, 72 mm on 80 mm paper.
  static int dotsFor(PaperSize paper) => paper == PaperSize.mm58 ? 384 : 576;

  /// The receipt page is the paper width, with 8 pt margins that the printer cannot use.
  static const double _marginPt = 8;

  static double _pageWidthPt(PaperSize paper) => paper == PaperSize.mm58 ? PdfPageFormat.roll57.width : PdfPageFormat.roll80.width;

  /// Renders the first page of the receipt PDF and converts it into an ESC/POS job.
  static Future<List<int>> buildJob(Uint8List pdf, PaperSize paper, PrinterConfig config) async {
    final dots = dotsFor(paper);
    final contentPt = _pageWidthPt(paper) - _marginPt * 2;
    final dpi = dots / (contentPt / 72);
    final offset = (_marginPt * dpi / 72).round();
    await for (final page in Printing.raster(pdf, pages: const [0], dpi: dpi)) {
      final bytes = EscPos.raster(page.pixels, page.width, page.height, outWidth: dots, offsetX: offset);
      return EscPos.job(bytes, cutPaper: config.cutPaper, openCashDrawer: config.openDrawer);
    }
    throw Exception('The receipt could not be prepared for printing.');
  }

  /// Sends the receipt to the printer set up on this device. Returns false when no printer is set up (the caller then
  /// uses the system print dialog). Throws when a set-up printer cannot be reached.
  static Future<bool> printPdf(Uint8List pdf, {required PaperSize paper}) async {
    if (!thermalSupported || paper == PaperSize.a4) return false;
    final config = await PrinterConfig.load();
    if (!config.isConfigured) return false;
    final job = await buildJob(pdf, paper, config);
    await sendToPrinter(config, job);
    return true;
  }

  /// Used by the setup screen: prints a short test receipt and reports the real error.
  static Future<void> printTest(PrinterConfig config, PaperSize paper, Uint8List pdf) async {
    final job = await buildJob(pdf, paper, config);
    await sendToPrinter(config, job);
  }

  /// Called when a set-up printer fails during normal printing: tells the person once, then the system dialog opens.
  static void reportFailure(Object error) {
    final msg = error.toString().replaceFirst('Exception: ', '');
    showGlobalToast('Printer problem: $msg The system print dialog is used instead.', error: true);
  }
}
