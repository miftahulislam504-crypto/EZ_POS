import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/format.dart';
import 'surfaces.dart';

/// Summary figure with a smooth count-up when the value changes.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = Tone.brand,
    this.caption,
    this.onTap,
    this.formatter,
    this.isMoney = true,
  });

  final String label;
  final num value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;
  final String Function(num)? formatter;
  final bool isMoney;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final format = formatter ?? (isMoney ? (num v) => Fmt.money(v) : (num v) => Fmt.whole(v.round()));
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconBadge(icon, tone: tone, size: 36),
              const Spacer(),
              if (onTap != null) Icon(Icons.arrow_outward_rounded, size: 16, color: c.textMuted),
            ],
          ),
          const SizedBox(height: 14),
          Text(label, style: context.text.labelLarge?.copyWith(color: c.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                format(v),
                style: context.text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
