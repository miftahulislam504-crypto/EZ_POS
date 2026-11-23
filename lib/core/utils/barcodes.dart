import 'dart:math';

class Barcodes {
  Barcodes._();

  /// Keeps only digits and limits the prefix to 6 so at least 6 random digits remain. Falls back to 20.
  static String cleanPrefix(String? prefix) {
    final digits = (prefix ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '20';
    return digits.length > 6 ? digits.substring(0, 6) : digits;
  }

  /// EAN-13 check digit for the first 12 digits.
  static int ean13Check(String body12) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = int.parse(body12[i]);
      sum += i.isEven ? d : d * 3;
    }
    return (10 - sum % 10) % 10;
  }

  static bool isValidEan13(String code) {
    if (!RegExp(r'^[0-9]{13}$').hasMatch(code)) return false;
    return ean13Check(code.substring(0, 12)) == int.parse(code[12]);
  }

  /// Generates an internal EAN-13 code. The prefix comes from the business rules (default 20, reserved for in-store use).
  static String generateEan13({String prefix = '20', Random? random}) {
    final r = random ?? Random.secure();
    final pre = cleanPrefix(prefix);
    final body = '$pre${List.generate(12 - pre.length, (_) => r.nextInt(10)).join()}';
    return '$body${ean13Check(body)}';
  }
}
