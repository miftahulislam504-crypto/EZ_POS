double dbl(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

double? dblOrNull(dynamic v) => v == null ? null : dbl(v);

int intOf(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

String? nonEmpty(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

Map<String, dynamic> asMap(dynamic v) => Map<String, dynamic>.from(v as Map);
List<Map<String, dynamic>> asRows(dynamic v) => [for (final r in (v as List? ?? const [])) asMap(r)];

/// Strips characters that break PostgREST or() filters.
String safeSearch(String s) => s.replaceAll(RegExp(r'[,()%*\\]'), ' ').trim();
