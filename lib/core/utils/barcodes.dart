import 'dart:math';

class Barcodes {
  Barcodes._();

  /// Generates an internal EAN-13 code (prefix 20 is reserved for in-store use).
  static String generateEan13() {
    final r = Random.secure();
    final body = '20${List.generate(10, (_) => r.nextInt(10)).join()}';
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = int.parse(body[i]);
      sum += i.isEven ? d : d * 3;
    }
    final check = (10 - sum % 10) % 10;
    return '$body$check';
  }
}
