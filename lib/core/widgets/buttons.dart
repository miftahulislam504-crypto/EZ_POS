import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum ButtonKind { primary, secondary, danger, text }

class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
    this.kind = ButtonKind.primary,
    this.loading = false,
    this.expand = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonKind kind;
  final bool loading;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !loading;
    final VoidCallback? tap = enabled ? onPressed : null;
    final fg = kind == ButtonKind.primary || kind == ButtonKind.danger ? Colors.white : c.text;

    final Widget child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: kind == ButtonKind.primary || kind == ButtonKind.danger ? Colors.white : c.primary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    final minSize = Size(dense ? 44 : 64, dense ? 40 : 48);
    final Widget button = switch (kind) {
      ButtonKind.primary => FilledButton(
          onPressed: tap, style: FilledButton.styleFrom(minimumSize: minSize), child: child),
      ButtonKind.danger => FilledButton(
          onPressed: tap,
          style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: fg, minimumSize: minSize),
          child: child),
      ButtonKind.secondary => OutlinedButton(
          onPressed: tap, style: OutlinedButton.styleFrom(minimumSize: minSize), child: child),
      ButtonKind.text => TextButton(onPressed: tap, style: TextButton.styleFrom(minimumSize: minSize), child: child),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
