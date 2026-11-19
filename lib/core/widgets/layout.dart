import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../theme/app_colors.dart';
import 'buttons.dart';

class Breakpoints {
  Breakpoints._();
  static const double wide = 900;
  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= wide;
  static bool isPhone(BuildContext c) => MediaQuery.sizeOf(c).width < 600;
}

class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 1200, this.padding});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: content),
    );
  }
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.floatingActionButton,
    this.bottom,
    this.bottomBar,
    this.maxWidth = 1200,
    this.backgroundColor,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;
  final Widget? bottomBar;
  final double maxWidth;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: subtitle == null
            ? Text(title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  Text(subtitle!,
                      style: context.text.bodySmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600)),
                ],
              ),
        actions: [...?actions, const SizedBox(width: 8)],
        bottom: bottom,
      ),
      body: ResponsiveCenter(maxWidth: maxWidth, child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar,
    );
  }
}

/// Full-screen form with a sticky save bar.
class FormScaffold extends StatelessWidget {
  const FormScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.formKey,
    this.saving = false,
    this.saveLabel = 'Save',
    this.actions,
    this.maxWidth = 760,
    this.secondary,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final GlobalKey<FormState>? formKey;
  final bool saving;
  final String saveLabel;
  final List<Widget>? actions;
  final double maxWidth;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [...?actions, const SizedBox(width: 8)]),
      body: Form(
        key: formKey,
        child: ResponsiveCenter(
          maxWidth: maxWidth,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: children,
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
        child: SafeArea(
          top: false,
          child: ResponsiveCenter(
            maxWidth: maxWidth,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                if (secondary != null) ...[secondary!, const SizedBox(width: 12)],
                Expanded(child: AppButton(saveLabel, onPressed: onSave, loading: saving, expand: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Group of related form fields with a small heading.
class FormSection extends StatelessWidget {
  const FormSection(this.title, {super.key, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: context.text.bodySmall?.copyWith(color: c.textMuted)),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Two fields side by side on wide screens, stacked on phones.
class FieldRow extends StatelessWidget {
  const FieldRow(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isPhone(context)) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Bottom sheet on phones, centred dialog on wide screens.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  double maxWidth = 520,
}) {
  Widget frame(BuildContext ctx) => _SheetFrame(title: title, child: builder(ctx));
  if (Breakpoints.isWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
          child: frame(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: frame(ctx),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = Breakpoints.isWide(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, wide ? 18 : 0, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text(title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Shows [child] only when the signed-in user holds [permission].
class PermissionGate extends ConsumerWidget {
  const PermissionGate({super.key, required this.permission, required this.child, this.fallback});

  final String permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    if (user != null && user.can(permission)) return child;
    return fallback ?? const SizedBox.shrink();
  }
}

/// Scrollable list of fixed-height rows that becomes a multi-column grid on wide screens.
class AdaptiveList extends StatelessWidget {
  const AdaptiveList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.rowHeight = 84,
    this.maxTileWidth = 560,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 96),
    this.footer,
    this.header,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double rowHeight;
  final double maxTileWidth;
  final EdgeInsetsGeometry padding;
  final Widget? footer;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (header != null) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: header)),
        SliverPadding(
          padding: padding,
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxTileWidth,
              mainAxisExtent: rowHeight,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
          ),
        ),
        if (footer != null) SliverToBoxAdapter(child: footer),
      ],
    );
  }
}
