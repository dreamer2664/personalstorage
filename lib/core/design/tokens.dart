import 'dart:ui';

import 'package:flutter/cupertino.dart';

/// Colour roles for one brightness. Screens never hard-code colours: they read a [PsPalette] via
/// `context.ps`, which keeps light/dark parity and makes re-theming a one-file change.
@immutable
class PsPalette {
  const PsPalette({
    required this.brightness,
    required this.background,
    required this.backgroundTint,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.separator,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.accent,
    required this.accentSoft,
    required this.danger,
    required this.success,
    required this.warning,
    required this.shadow,
    required this.blobs,
  });

  final Brightness brightness;
  final Color background;
  final Color backgroundTint;

  /// Translucent surface used by cards and bars (kept light so the blur shows through).
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassBorder;
  final Color separator;
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color accent;
  final Color accentSoft;
  final Color danger;
  final Color success;
  final Color warning;
  final Color shadow;

  /// Colours of the ambient background blobs.
  final List<Color> blobs;

  bool get isDark => brightness == Brightness.dark;

  static const PsPalette light = PsPalette(
    brightness: Brightness.light,
    background: Color(0xFFF2F2F7),
    backgroundTint: Color(0xFFFFFFFF),
    glassFill: Color(0xA8FFFFFF),
    glassFillStrong: Color(0xD9FFFFFF),
    glassBorder: Color(0x8CFFFFFF),
    separator: Color(0x1F3C3C43),
    label: Color(0xFF1C1C1E),
    secondaryLabel: Color(0x993C3C43),
    tertiaryLabel: Color(0x4D3C3C43),
    accent: Color(0xFF0A84FF),
    accentSoft: Color(0x1F0A84FF),
    danger: Color(0xFFFF3B30),
    success: Color(0xFF30B350),
    warning: Color(0xFFFF9F0A),
    shadow: Color(0x14000000),
    blobs: [Color(0x330A84FF), Color(0x29BF5AF2), Color(0x2930D5C8), Color(0x29FF9F0A)],
  );

  static const PsPalette dark = PsPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0B10),
    backgroundTint: Color(0xFF16161D),
    glassFill: Color(0x8C2C2C32),
    glassFillStrong: Color(0xCC1C1C22),
    glassBorder: Color(0x1FFFFFFF),
    separator: Color(0x29FFFFFF),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5),
    tertiaryLabel: Color(0x4DEBEBF5),
    accent: Color(0xFF0A84FF),
    accentSoft: Color(0x380A84FF),
    danger: Color(0xFFFF453A),
    success: Color(0xFF32D74B),
    warning: Color(0xFFFF9F0A),
    shadow: Color(0x66000000),
    blobs: [Color(0x440A84FF), Color(0x38BF5AF2), Color(0x2E30D5C8), Color(0x26FF375F)],
  );
}

/// Spacing scale (4-pt grid).
abstract final class PsSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Surfaces use continuous ("squircle") corners via `RoundedSuperellipseBorder`.
abstract final class PsRadius {
  static const double chip = 12;
  static const double card = 22;
  static const double sheet = 28;
  static const double bar = 26;
}

/// Motion language: short, springy, never linear.
abstract final class PsMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve spring = Curves.easeOutBack;

  static const SpringDescription springDesc = SpringDescription(mass: 1, stiffness: 420, damping: 30);
}

/// Text styles (Inter ≈ SF Pro). Sizes follow the iOS type ramp.
abstract final class PsText {
  static const String family = 'Inter';

  static TextStyle _s(double size, FontWeight w, Color c, {double? height, double? spacing}) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: w,
    color: c,
    height: height,
    letterSpacing: spacing,
    decoration: TextDecoration.none,
  );

  static TextStyle largeTitle(Color c) => _s(34, FontWeight.w700, c, height: 1.12, spacing: -0.9);
  static TextStyle title(Color c) => _s(22, FontWeight.w600, c, height: 1.2, spacing: -0.4);
  static TextStyle headline(Color c) => _s(17, FontWeight.w600, c, height: 1.25, spacing: -0.3);
  static TextStyle body(Color c) => _s(17, FontWeight.w400, c, height: 1.38, spacing: -0.25);
  static TextStyle callout(Color c) => _s(16, FontWeight.w400, c, height: 1.3, spacing: -0.2);
  static TextStyle subhead(Color c) => _s(15, FontWeight.w400, c, height: 1.3, spacing: -0.15);
  static TextStyle footnote(Color c) => _s(13, FontWeight.w400, c, height: 1.3, spacing: -0.05);
  static TextStyle caption(Color c) => _s(12, FontWeight.w500, c, height: 1.25);
  static TextStyle chip(Color c) => _s(12.5, FontWeight.w600, c, height: 1.1, spacing: -0.05);
}

/// Squircle shape helper.
ShapeBorder squircle(double radius, {BorderSide side = BorderSide.none}) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius), side: side);

/// Blur amount for glass surfaces, reduced on low-end devices via [GlassQuality].
abstract final class GlassQuality {
  static double sigma = 24;
  static ImageFilter get filter => ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
}
