import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';
import 'layout.dart';

/// Text field with the label stacked above it.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.keyboardType,
    this.validator,
    this.prefixIcon,
    this.prefixText,
    this.suffix,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.autofocus = false,
    this.enabled = true,
    this.obscure = false,
    this.focusNode,
    this.helper,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  final String? prefixText;
  final Widget? suffix;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final bool enabled;
  final bool obscure;
  final FocusNode? focusNode;
  final String? helper;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: obscure ? 1 : maxLines,
      readOnly: readOnly,
      onTap: onTap,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscure,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        prefixText: prefixText,
        suffixIcon: suffix,
        helperText: helper,
        fillColor: enabled ? c.surface : c.surfaceMuted,
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(label!, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: c.textMuted)),
        ),
        field,
      ],
    );
  }
}

/// Decimal amount input with the currency symbol prefix.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    this.controller,
    this.label,
    this.hint = '0.00',
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.decimals = 2,
    this.showSymbol = true,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? label;
  final String hint;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final int decimals;
  final bool showSymbol;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      validator: validator,
      onChanged: onChanged,
      autofocus: autofocus,
      enabled: enabled,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      prefixText: showSymbol ? '${AppConfig.currencySymbol} ' : null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('^\\d*\\.?\\d{0,$decimals}'))],
    );
  }
}

/// Search box with debounce.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.controller,
    this.onSubmitted,
    this.autofocus = false,
    this.debounce = const Duration(milliseconds: 300),
    this.trailing,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Duration debounce;
  final Widget? trailing;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(v.trim()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: _changed,
      onSubmitted: (v) {
        _timer?.cancel();
        widget.onChanged(v.trim());
        widget.onSubmitted?.call(v.trim());
      },
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: Icon(Icons.search_rounded, color: c.textMuted),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _controller.clear();
                  _timer?.cancel();
                  widget.onChanged('');
                  setState(() {});
                },
              )
            : widget.trailing,
      ),
    );
  }
}

class PickerOption<T> {
  const PickerOption(this.value, this.label, {this.subtitle});
  final T value;
  final String label;
  final String? subtitle;
}

class _Picked<T> {
  const _Picked(this.value);
  final T? value;
}

/// Tap-to-choose field. Opens a sheet (dialog on wide screens) so it behaves the same on every platform.
class PickerField<T> extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.hint = 'Select',
    this.allowClear = false,
    this.errorText,
    this.enabled = true,
    this.searchable = false,
    this.leading,
  });

  final String label;
  final String hint;
  final T? value;
  final List<PickerOption<T>> options;
  final ValueChanged<T?> onChanged;
  final bool allowClear;
  final String? errorText;
  final bool enabled;
  final bool searchable;
  final IconData? leading;

  PickerOption<T>? get _selected {
    for (final o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final result = await showAppSheet<_Picked<T>>(
      context,
      title: label,
      builder: (ctx) => _PickerList<T>(options: options, selected: value, allowClear: allowClear, searchable: searchable),
    );
    if (result != null) onChanged(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sel = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(label, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: c.textMuted)),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => _open(context) : null,
          child: InputDecorator(
            decoration: InputDecoration(
              errorText: errorText,
              prefixIcon: leading == null ? null : Icon(leading, size: 20),
              suffixIcon: const Icon(Icons.unfold_more_rounded, size: 20),
              fillColor: enabled ? c.surface : c.surfaceMuted,
            ),
            child: Text(
              sel?.label ?? hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: sel == null ? c.textMuted.withValues(alpha: 0.75) : c.text),
            ),
          ),
        ),
      ],
    );
  }
}

class _PickerList<T> extends StatefulWidget {
  const _PickerList({required this.options, required this.selected, required this.allowClear, required this.searchable});

  final List<PickerOption<T>> options;
  final T? selected;
  final bool allowClear;
  final bool searchable;

  @override
  State<_PickerList<T>> createState() => _PickerListState<T>();
}

class _PickerListState<T> extends State<_PickerList<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = widget.options.where((o) => _q.isEmpty || o.label.toLowerCase().contains(_q.toLowerCase())).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.searchable || widget.options.length > 8)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SearchField(hint: 'Search', onChanged: (v) => setState(() => _q = v)),
          ),
        if (widget.allowClear)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block_rounded),
            title: const Text('None'),
            onTap: () => Navigator.pop(context, _Picked<T>(null)),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('Nothing found', style: TextStyle(color: c.textMuted))),
          ),
        for (final o in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: o.subtitle == null ? null : Text(o.subtitle!),
            trailing: o.value == widget.selected ? Icon(Icons.check_circle_rounded, color: c.primary) : null,
            onTap: () => Navigator.pop(context, _Picked<T>(o.value)),
          ),
      ],
    );
  }
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.allowClear = false,
    this.hint = 'Select date',
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool allowClear;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(label, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: c.textMuted)),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: firstDate ?? DateTime(now.year - 10),
              lastDate: lastDate ?? DateTime(now.year + 10),
            );
            if (picked != null) onChanged(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
              suffixIcon: allowClear && value != null
                  ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null))
                  : null,
            ),
            child: Text(
              value == null ? hint : Fmt.date(value),
              style: TextStyle(fontWeight: FontWeight.w600, color: value == null ? c.textMuted.withValues(alpha: 0.75) : c.text),
            ),
          ),
        ),
      ],
    );
  }
}
