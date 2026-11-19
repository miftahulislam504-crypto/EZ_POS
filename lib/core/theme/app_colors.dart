import 'package:flutter/material.dart';

/// Semantic colours that are not part of Material's ColorScheme.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primarySoft,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.sidebar,
    required this.sidebarText,
    required this.sidebarMuted,
    required this.sidebarActive,
  });

  final Color primary;
  final Color primarySoft;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color sidebar;
  final Color sidebarText;
  final Color sidebarMuted;
  final Color sidebarActive;

  // Ink and jade: deep spruce neutrals, one confident green, saffron for attention.
  static const light = AppColors(
    primary: Color(0xFF0B6B5D),
    primarySoft: Color(0xFFDCEFEA),
    accent: Color(0xFFD9822B),
    background: Color(0xFFF4F6F5),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF2F0),
    border: Color(0xFFE0E6E3),
    text: Color(0xFF0E1F1C),
    textMuted: Color(0xFF65756F),
    success: Color(0xFF15803D),
    successSoft: Color(0xFFDDF3E4),
    warning: Color(0xFFB45309),
    warningSoft: Color(0xFFFBEBD3),
    danger: Color(0xFFBE3A34),
    dangerSoft: Color(0xFFFBE3E1),
    info: Color(0xFF1D5FA8),
    infoSoft: Color(0xFFDCE9F8),
    sidebar: Color(0xFF0A1F1C),
    sidebarText: Color(0xFFE6F0EE),
    sidebarMuted: Color(0xFF8BA39E),
    sidebarActive: Color(0xFF14423B),
  );

  static const dark = AppColors(
    primary: Color(0xFF3FBFA8),
    primarySoft: Color(0xFF123A34),
    accent: Color(0xFFF0A24B),
    background: Color(0xFF0A1412),
    surface: Color(0xFF111F1C),
    surfaceMuted: Color(0xFF182B27),
    border: Color(0xFF233935),
    text: Color(0xFFE7F0EE),
    textMuted: Color(0xFF93A8A3),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF12301F),
    warning: Color(0xFFF5B25B),
    warningSoft: Color(0xFF3A2A10),
    danger: Color(0xFFF08A84),
    dangerSoft: Color(0xFF3A1A18),
    info: Color(0xFF7DB4EE),
    infoSoft: Color(0xFF142A44),
    sidebar: Color(0xFF07100E),
    sidebarText: Color(0xFFE6F0EE),
    sidebarMuted: Color(0xFF7F9892),
    sidebarActive: Color(0xFF12332E),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
