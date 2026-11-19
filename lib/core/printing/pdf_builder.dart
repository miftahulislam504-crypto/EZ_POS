import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/app_user.dart';
import '../utils/format.dart';

class PrintLine {
  const PrintLine({required this.name, required this.qty, required this.price, this.discount = 0, required this.total, this.sub});

  final String name;
  final String qty;
  final double price;
  final double discount;
  final double total;
  final String? sub;
}

/// Everything needed to print an invoice, purchase bill or payment receipt.
class PrintableDoc {
  const PrintableDoc({
    required this.title,
    required this.number,
    required this.date,
    this.partyLabel = 'Customer',
    this.partyName,
    this.partyPhone,
    this.partyAddress,
    this.meta = const [],
    this.lines = const [],
    this.totals = const [],
    this.payments = const [],
    this.note,
    this.status,
    this.qrData,
  });

  final String title;
  final String number;
  final DateTime date;
  final String partyLabel;
  final String? partyName;
  final String? partyPhone;
  final String? partyAddress;
  final List<(String, String)> meta;
  final List<PrintLine> lines;

  /// (label, value, strong)
  final List<(String, String, bool)> totals;
  final List<(String, String)> payments;
  final String? note;
  final String? status;
  final String? qrData;
}

enum PaperSize { mm58, mm80, a4 }

PaperSize paperFromSetting(String s) => switch (s) {
      '58mm' => PaperSize.mm58,
      'a4' || 'A4' => PaperSize.a4,
      _ => PaperSize.mm80,
    };

class PdfBuilder {
  PdfBuilder._();

  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> _loadTheme() async {
    if (_theme != null) return _theme!;
    try {
      final base = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      final bn = await PdfGoogleFonts.notoSansBengaliRegular();
      _theme = pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [bn]);
    } catch (_) {
      _theme = pw.ThemeData.base();
    }
    return _theme!;
  }

  static Future<Uint8List> build(PrintableDoc doc, Business business, {PaperSize paper = PaperSize.mm80}) async {
    final theme = await _loadTheme();
    final pdf = pw.Document(title: '${doc.title} ${doc.number}', author: business.name, theme: theme);
    if (paper == PaperSize.a4) {
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => _a4(doc, business),
      ));
    } else {
      final fmt = paper == PaperSize.mm58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
      pdf.addPage(pw.Page(
        pageFormat: fmt.copyWith(marginLeft: 8, marginRight: 8, marginTop: 10, marginBottom: 14),
        build: (_) => _roll(doc, business, small: paper == PaperSize.mm58),
      ));
    }
    return pdf.save();
  }

  // ------------------------------------------------------------- thermal roll
  static pw.Widget _roll(PrintableDoc d, Business b, {required bool small}) {
    final f = small ? 7.5 : 9.0;
    pw.TextStyle s({bool bold = false, double? size}) =>
        pw.TextStyle(fontSize: size ?? f, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    final dashed = pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.6, height: 8);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(child: pw.Text(b.name, style: s(bold: true, size: f + 3), textAlign: pw.TextAlign.center)),
        if ((b.address ?? '').isNotEmpty) pw.Center(child: pw.Text(b.address!, style: s(), textAlign: pw.TextAlign.center)),
        if ((b.phone ?? '').isNotEmpty) pw.Center(child: pw.Text('Tel: ${b.phone}', style: s())),
        dashed,
        pw.Center(child: pw.Text(d.title.toUpperCase(), style: s(bold: true, size: f + 1))),
        pw.SizedBox(height: 3),
        _kv('No', d.number, s()),
        _kv('Date', Fmt.dateTime(d.date), s()),
        for (final m in d.meta) _kv(m.$1, m.$2, s()),
        if ((d.partyName ?? '').isNotEmpty) _kv(d.partyLabel, d.partyName!, s()),
        if ((d.partyPhone ?? '').isNotEmpty) _kv('Phone', d.partyPhone!, s()),
        if (d.lines.isNotEmpty) ...[
          dashed,
          for (final l in d.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(l.name, style: s(bold: true)),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('${l.qty} x ${Fmt.pdfMoney(l.price)}${l.discount > 0 ? '  (-${Fmt.pdfMoney(l.discount)})' : ''}', style: s()),
                      pw.Text(Fmt.pdfMoney(l.total), style: s(bold: true)),
                    ],
                  ),
                ],
              ),
            ),
        ],
        dashed,
        for (final t in d.totals) _kv(t.$1, t.$2, s(bold: t.$3, size: t.$3 ? f + 1 : null)),
        if (d.payments.isNotEmpty) ...[
          dashed,
          for (final p in d.payments) _kv(p.$1, p.$2, s()),
        ],
        if ((d.note ?? '').isNotEmpty) ...[pw.SizedBox(height: 4), pw.Text('Note: ${d.note}', style: s())],
        dashed,
        if (b.invoiceFooter.isNotEmpty) pw.Center(child: pw.Text(b.invoiceFooter, style: s(), textAlign: pw.TextAlign.center)),
        if (b.invoiceTerms.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text(b.invoiceTerms, style: s(size: f - 1), textAlign: pw.TextAlign.center)),
        if (d.qrData != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: d.qrData!, width: small ? 56 : 70, height: small ? 56 : 70)),
          ),
      ],
    );
  }

  static pw.Widget _kv(String k, String v, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Text(k, style: style)),
            pw.SizedBox(width: 6),
            pw.Text(v, style: style, textAlign: pw.TextAlign.right),
          ],
        ),
      );

  // ------------------------------------------------------------- A4
  static List<pw.Widget> _a4(PrintableDoc d, Business b) {
    const ink = PdfColor.fromInt(0xFF0E1F1C);
    const muted = PdfColor.fromInt(0xFF65756F);
    const accent = PdfColor.fromInt(0xFF0B6B5D);
    const line = PdfColor.fromInt(0xFFE0E6E3);

    pw.Widget cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left, PdfColor color = ink}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(t, textAlign: align, style: pw.TextStyle(fontSize: 10, color: color, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(b.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: accent)),
              if ((b.address ?? '').isNotEmpty) pw.Text(b.address!, style: const pw.TextStyle(fontSize: 10, color: muted)),
              if ((b.phone ?? '').isNotEmpty) pw.Text('Phone: ${b.phone}', style: const pw.TextStyle(fontSize: 10, color: muted)),
              if ((b.email ?? '').isNotEmpty) pw.Text(b.email!, style: const pw.TextStyle(fontSize: 10, color: muted)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(d.title.toUpperCase(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: ink)),
              pw.Text(d.number, style: const pw.TextStyle(fontSize: 11, color: muted)),
              if (d.status != null) pw.Text(d.status!, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: accent)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(d.partyLabel.toUpperCase(), style: const pw.TextStyle(fontSize: 8, color: muted)),
                  pw.SizedBox(height: 3),
                  pw.Text(d.partyName ?? 'Walk-in customer', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  if ((d.partyPhone ?? '').isNotEmpty) pw.Text(d.partyPhone!, style: const pw.TextStyle(fontSize: 10)),
                  if ((d.partyAddress ?? '').isNotEmpty) pw.Text(d.partyAddress!, style: const pw.TextStyle(fontSize: 10, color: muted)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Date: ${Fmt.dateTime(d.date)}', style: const pw.TextStyle(fontSize: 10)),
                  for (final m in d.meta) pw.Text('${m.$1}: ${m.$2}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 16),
      if (d.lines.isNotEmpty)
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.6), bottom: pw.BorderSide(color: line)),
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.3),
            5: const pw.FlexColumnWidth(1.7),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF2F0)),
              children: [
                cell('#', bold: true),
                cell('Item', bold: true),
                cell('Qty', bold: true, align: pw.TextAlign.right),
                cell('Price', bold: true, align: pw.TextAlign.right),
                cell('Disc.', bold: true, align: pw.TextAlign.right),
                cell('Total', bold: true, align: pw.TextAlign.right),
              ],
            ),
            for (var i = 0; i < d.lines.length; i++)
              pw.TableRow(children: [
                cell('${i + 1}', color: muted),
                cell(d.lines[i].sub == null ? d.lines[i].name : '${d.lines[i].name}\n${d.lines[i].sub}'),
                cell(d.lines[i].qty, align: pw.TextAlign.right),
                cell(Fmt.pdfMoney(d.lines[i].price), align: pw.TextAlign.right),
                cell(d.lines[i].discount > 0 ? Fmt.pdfMoney(d.lines[i].discount) : '-', align: pw.TextAlign.right),
                cell(Fmt.pdfMoney(d.lines[i].total), bold: true, align: pw.TextAlign.right),
              ]),
          ],
        ),
      pw.SizedBox(height: 14),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (d.payments.isNotEmpty) ...[
                  pw.Text('PAYMENTS', style: const pw.TextStyle(fontSize: 8, color: muted)),
                  pw.SizedBox(height: 3),
                  for (final p in d.payments) pw.Text('${p.$1}: ${p.$2}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 8),
                ],
                if ((d.note ?? '').isNotEmpty) pw.Text('Note: ${d.note}', style: const pw.TextStyle(fontSize: 10, color: muted)),
                if (d.qrData != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 10),
                    child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: d.qrData!, width: 64, height: 64),
                  ),
              ],
            ),
          ),
          pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                for (final t in d.totals)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(t.$1, style: pw.TextStyle(fontSize: t.$3 ? 12 : 10, fontWeight: t.$3 ? pw.FontWeight.bold : pw.FontWeight.normal, color: t.$3 ? ink : muted)),
                        pw.Text(t.$2, style: pw.TextStyle(fontSize: t.$3 ? 12 : 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 28),
      pw.Divider(color: line),
      if (b.invoiceFooter.isNotEmpty) pw.Center(child: pw.Text(b.invoiceFooter, style: const pw.TextStyle(fontSize: 10, color: muted))),
      if (b.invoiceTerms.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(b.invoiceTerms, style: const pw.TextStyle(fontSize: 8, color: muted))),
    ];
  }

  // ------------------------------------------------------------- actions
  static Future<void> printDoc(PrintableDoc doc, Business business, {PaperSize? paper}) async {
    final size = paper ?? paperFromSetting(business.paperSize);
    final bytes = await build(doc, business, paper: size);
    await Printing.layoutPdf(
      name: '${doc.title} ${doc.number}',
      onLayout: (_) async => bytes,
      format: size == PaperSize.a4 ? PdfPageFormat.a4 : (size == PaperSize.mm58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80),
    );
  }

  static Future<void> shareDoc(PrintableDoc doc, Business business, {PaperSize? paper}) async {
    final size = paper ?? paperFromSetting(business.paperSize);
    final bytes = await build(doc, business, paper: size);
    await Printing.sharePdf(bytes: bytes, filename: '${doc.number}.pdf');
  }

  // ------------------------------------------------------------- barcode labels
  static Future<void> printLabels(List<LabelItem> items, LabelSpec spec) async {
    final theme = await _loadTheme();
    final pdf = pw.Document(theme: theme, title: 'Barcode labels');
    final labels = <LabelItem>[
      for (final i in items) for (var n = 0; n < i.copies; n++) i,
    ];
    pw.Widget label(LabelItem i) => pw.Container(
          width: spec.width,
          height: spec.height,
          padding: const pw.EdgeInsets.all(4),
          decoration: spec.sheet ? pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 0.4)) : null,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (spec.showName) pw.Text(i.name, maxLines: 1, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: i.code, drawText: true, textStyle: const pw.TextStyle(fontSize: 7)),
                ),
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (spec.showSku) pw.Text(i.sku ?? '', style: const pw.TextStyle(fontSize: 6.5)),
                  if (spec.showPrice) pw.Text(Fmt.pdfMoney(i.price), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        );

    if (spec.sheet) {
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [pw.Wrap(spacing: 0, runSpacing: 0, children: [for (final l in labels) label(l)])],
      ));
    } else {
      final fmt = PdfPageFormat(spec.width, spec.height, marginAll: 0);
      for (final l in labels) {
        pdf.addPage(pw.Page(pageFormat: fmt, margin: pw.EdgeInsets.zero, build: (_) => label(l)));
      }
    }
    final bytes = await pdf.save();
    await Printing.layoutPdf(name: 'Barcode labels', onLayout: (_) async => bytes);
  }
}

class LabelItem {
  const LabelItem({required this.name, required this.code, this.sku, this.price = 0, this.copies = 1});

  final String name;
  final String code;
  final String? sku;
  final double price;
  final int copies;

  LabelItem withCopies(int n) => LabelItem(name: name, code: code, sku: sku, price: price, copies: n);
}

class LabelSpec {
  const LabelSpec({required this.width, required this.height, this.sheet = false, this.showName = true, this.showPrice = true, this.showSku = true});

  final double width;
  final double height;
  final bool sheet;
  final bool showName;
  final bool showPrice;
  final bool showSku;

  LabelSpec copyWith({bool? showName, bool? showPrice, bool? showSku}) => LabelSpec(
        width: width,
        height: height,
        sheet: sheet,
        showName: showName ?? this.showName,
        showPrice: showPrice ?? this.showPrice,
        showSku: showSku ?? this.showSku,
      );

  static const mm50x30 = LabelSpec(width: 50 * PdfPageFormat.mm, height: 30 * PdfPageFormat.mm);
  static const mm40x25 = LabelSpec(width: 40 * PdfPageFormat.mm, height: 25 * PdfPageFormat.mm);
  static const a4Sheet = LabelSpec(width: 64 * PdfPageFormat.mm, height: 34 * PdfPageFormat.mm, sheet: true);
}
