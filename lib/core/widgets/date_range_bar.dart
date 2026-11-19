import 'package:flutter/material.dart';

import '../utils/format.dart';

enum RangePreset { today, yesterday, last7, last30, thisMonth, custom }

class DateRange {
  const DateRange(this.from, this.to, this.preset);

  final DateTime from;
  final DateTime to;
  final RangePreset preset;

  static DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

  factory DateRange.of(RangePreset p) {
    final today = _d(DateTime.now());
    switch (p) {
      case RangePreset.today:
        return DateRange(today, today, p);
      case RangePreset.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return DateRange(y, y, p);
      case RangePreset.last7:
        return DateRange(today.subtract(const Duration(days: 6)), today, p);
      case RangePreset.last30:
        return DateRange(today.subtract(const Duration(days: 29)), today, p);
      case RangePreset.thisMonth:
        return DateRange(DateTime(today.year, today.month, 1), today, p);
      case RangePreset.custom:
        return DateRange(today, today, p);
    }
  }

  String get fromIso => Fmt.iso(from);
  String get toIso => Fmt.iso(to);

  /// Inclusive start and exclusive end as timestamps, for timestamptz filters.
  String get fromTs => DateTime(from.year, from.month, from.day).toUtc().toIso8601String();
  String get toTsExclusive => DateTime(to.year, to.month, to.day).add(const Duration(days: 1)).toUtc().toIso8601String();

  String get label => from == to ? Fmt.date(from) : '${Fmt.date(from)} - ${Fmt.date(to)}';

  @override
  bool operator ==(Object other) => other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class DateRangeBar extends StatelessWidget {
  const DateRangeBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.presets = const [
      RangePreset.today,
      RangePreset.yesterday,
      RangePreset.last7,
      RangePreset.last30,
      RangePreset.thisMonth,
      RangePreset.custom,
    ],
  });

  final DateRange value;
  final ValueChanged<DateRange> onChanged;
  final List<RangePreset> presets;

  static String _label(RangePreset p) => switch (p) {
        RangePreset.today => 'Today',
        RangePreset.yesterday => 'Yesterday',
        RangePreset.last7 => 'Last 7 days',
        RangePreset.last30 => 'Last 30 days',
        RangePreset.thisMonth => 'This month',
        RangePreset.custom => 'Custom',
      };

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: value.from, end: value.to),
    );
    if (picked != null) {
      onChanged(DateRange(DateTime(picked.start.year, picked.start.month, picked.start.day),
          DateTime(picked.end.year, picked.end.month, picked.end.day), RangePreset.custom));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in presets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p == RangePreset.custom && value.preset == RangePreset.custom ? value.label : _label(p)),
                selected: value.preset == p,
                onSelected: (_) => p == RangePreset.custom ? _pickCustom(context) : onChanged(DateRange.of(p)),
              ),
            ),
        ],
      ),
    );
  }
}
