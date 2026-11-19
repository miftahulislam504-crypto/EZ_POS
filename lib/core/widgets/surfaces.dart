import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/format.dart';

enum Tone { neutral, brand, success, warning, danger, info }

extension ToneColors on Tone {
  Color fg(BuildContext context) {
    final c = context.colors;
    return switch (this) {
      Tone.neutral => c.textMuted,
      Tone.brand => c.primary,
      Tone.success => c.success,
      Tone.warning => c.warning,
      Tone.danger => c.danger,
      Tone.info => c.info,
    };
  }

  Color bg(BuildContext context) {
    final c = context.colors;
    return switch (this) {
      Tone.neutral => c.surfaceMuted,
      Tone.brand => c.primarySoft,
      Tone.success => c.successSoft,
      Tone.warning => c.warningSoft,
      Tone.danger => c.dangerSoft,
      Tone.info => c.infoSoft,
    };
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor ?? c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing, this.padding});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = Tone.neutral, this.dense = false});

  final String label;
  final Tone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: tone.bg(context), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(color: tone.fg(context), fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.tone = Tone.brand, this.size = 40});

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.bg(context), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.5, color: tone.fg(context)),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, this.imageUrl});

  final String name;
  final double size;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : (parts.length == 1 ? parts[0][0] : parts[0][0] + parts[1][0]).toUpperCase();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(size * 0.34)),
      alignment: Alignment.center,
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? Image.network(imageUrl!, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(context, initials))
          : _initials(context, initials),
    );
  }

  Widget _initials(BuildContext context, String initials) => Text(
        initials,
        style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w800, fontSize: size * 0.36),
      );
}

/// Label on the left, value on the right. Used in summaries and receipts.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.valueColor, this.padding});

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: context.text.bodyMedium?.copyWith(
                    color: bold ? c.text : c.textMuted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                color: valueColor ?? c.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Money with tabular figures so columns line up.
class MoneyText extends StatelessWidget {
  const MoneyText(this.value, {super.key, this.style, this.color, this.signed = false, this.compact = false});

  final num? value;
  final TextStyle? style;
  final Color? color;
  final bool signed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v = (value ?? 0).toDouble();
    final base = style ?? context.text.bodyMedium;
    final text = compact ? Fmt.compactMoney(v) : Fmt.money(v);
    return Text(
      signed && v > 0 ? '+$text' : text,
      style: base?.copyWith(
        color: color ?? base.color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
