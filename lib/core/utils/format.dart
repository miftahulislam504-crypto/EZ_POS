import 'package:intl/intl.dart';

import '../config/app_config.dart';

/// Number, money and date formatting. Money uses South Asian grouping (12,34,567.00).
class Fmt {
  Fmt._();

  static final NumberFormat _money = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);
  static final NumberFormat _whole = NumberFormat.decimalPattern('en_IN');
  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _time = DateFormat('hh:mm a');
  static final DateFormat _day = DateFormat('EEE, dd MMM');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd');

  static String money(num? v, {bool symbol = true}) {
    final value = (v ?? 0).toDouble();
    final body = _money.format(value.abs());
    final sign = value < -0.004 ? '-' : '';
    return symbol ? '$sign${AppConfig.currencySymbol} $body' : '$sign$body';
  }

  /// Plain-ASCII money for PDF output where the Bengali taka sign may be missing from fonts.
  static String pdfMoney(num? v) {
    final value = (v ?? 0).toDouble();
    final sign = value < -0.004 ? '-' : '';
    return '$sign${_money.format(value.abs())}';
  }

  static String compactMoney(num? v) {
    final value = (v ?? 0).toDouble();
    final abs = value.abs();
    String body;
    if (abs >= 10000000) {
      body = '${(abs / 10000000).toStringAsFixed(2)} Cr';
    } else if (abs >= 100000) {
      body = '${(abs / 100000).toStringAsFixed(2)} L';
    } else if (abs >= 1000) {
      body = '${(abs / 1000).toStringAsFixed(1)} K';
    } else {
      body = abs.toStringAsFixed(0);
    }
    return '${value < 0 ? '-' : ''}${AppConfig.currencySymbol} $body';
  }

  static String qty(num? v) {
    final value = (v ?? 0).toDouble();
    if (value == value.roundToDouble()) return _whole.format(value);
    var s = value.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  static String whole(num? v) => _whole.format(v ?? 0);

  static String date(DateTime? d) => d == null ? '-' : _date.format(d);
  static String dateTime(DateTime? d) => d == null ? '-' : _dateTime.format(d);
  static String time(DateTime? d) => d == null ? '-' : _time.format(d);
  static String day(DateTime d) => _day.format(d);
  static String iso(DateTime d) => _iso.format(d);

  static double parse(String? s) => double.tryParse((s ?? '').replaceAll(',', '').trim()) ?? 0;

  static String pct(num? v) => '${qty(v)}%';
}

/// Integer-cents arithmetic so the app and the database agree to the paisa.
class Cents {
  Cents._();
  static int of(num v) => (v * 100).round();
  static double toDouble(int cents) => cents / 100;
}

double round2(num v) => (v * 100).round() / 100;
