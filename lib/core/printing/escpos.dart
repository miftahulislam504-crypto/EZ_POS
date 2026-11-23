import 'dart:typed_data';

/// Minimal ESC/POS encoder. The receipt is drawn as a picture (the same layout as the PDF receipt) and sent as a
/// raster image, so any language the PDF can show (including Bangla) prints correctly on every ESC/POS printer.
class EscPos {
  EscPos._();

  static const List<int> initialize = [0x1B, 0x40];

  /// Partial cut after feeding the paper to the cutter.
  static const List<int> cut = [0x1D, 0x56, 0x42, 0x00];

  /// Pulse pin 2 of the cash drawer connector.
  static const List<int> openDrawer = [0x1B, 0x70, 0x00, 0x19, 0xFA];

  static List<int> feed(int lines) => [0x1B, 0x64, lines.clamp(0, 255).toInt()];

  /// Rows sent per GS v 0 command. Small bands keep cheap printers with small buffers happy.
  static const int bandRows = 128;

  /// Converts RGBA pixels to 1-bit ESC/POS raster commands.
  ///
  /// Only the [outWidth] columns starting at [offsetX] are used (the page margins are dropped). A pixel prints black when
  /// it is dark enough and not transparent. Blank rows at the bottom are removed so no paper is wasted.
  static List<int> raster(
    Uint8List rgba,
    int srcWidth,
    int srcHeight, {
    required int outWidth,
    int offsetX = 0,
    int threshold = 160,
  }) {
    final bytesPerRow = (outWidth + 7) ~/ 8;
    final rows = <Uint8List>[];
    for (var y = 0; y < srcHeight; y++) {
      final row = Uint8List(bytesPerRow);
      for (var x = 0; x < outWidth; x++) {
        final sx = x + offsetX;
        if (sx >= srcWidth) break;
        final i = (y * srcWidth + sx) * 4;
        final a = rgba[i + 3];
        if (a < 128) continue;
        final lum = (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        if (lum < threshold) {
          row[x >> 3] |= 0x80 >> (x & 7);
        }
      }
      rows.add(row);
    }
    // Drop blank rows at the end.
    var last = rows.length;
    while (last > 0 && rows[last - 1].every((b) => b == 0)) {
      last--;
    }
    final out = <int>[];
    for (var start = 0; start < last; start += bandRows) {
      final h = (start + bandRows <= last) ? bandRows : last - start;
      out.addAll([0x1D, 0x76, 0x30, 0x00, bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF]);
      for (var r = start; r < start + h; r++) {
        out.addAll(rows[r]);
      }
    }
    return out;
  }

  /// A complete print job: initialise, the picture, a little paper feed, optional cut and drawer pulse.
  static List<int> job(List<int> rasterBytes, {bool cutPaper = true, bool openCashDrawer = false}) => [
        ...initialize,
        if (openCashDrawer) ...openDrawer,
        ...rasterBytes,
        ...feed(cutPaper ? 4 : 2),
        if (cutPaper) ...cut,
      ];
}
