import 'package:flutter/material.dart';

/// Design tokens for the "Macchia" identity: black canvas, one accent that
/// follows the artwork, spot-shaped covers.
///
/// Every colour, spacing step, radius, shadow and duration used by the app
/// comes from here. Nothing should hardcode a hex value at a call site: the
/// old code repeated `Color(0xFF5AC8FA)` in about twenty places, which made
/// a palette change a find-and-replace exercise.
class AppColors {
  const AppColors._();

  // --- Ink: the opaque substrate ------------------------------------------
  // These are deliberately opaque. The previous ColorScheme used a
  // translucent `surface` (0x1AFFFFFF), so every Material surface derived
  // from it — dialogs, menus, cards — composited 10% white over whatever
  // happened to be behind, which is what made text unreadable.
  static const ink900 = Color(0xFF000000); // app canvas: nero vero
  static const ink800 = Color(0xFF0B0B0B); // surface
  static const ink700 = Color(0xFF141414); // sheets
  static const ink600 = Color(0xFF1C1C1C); // dialogs
  static const ink500 = Color(0xFF262626); // inputs

  static const outline = Color(0xFF363636);
  static const outlineVariant = Color(0xFF202020);

  // --- Text ----------------------------------------------------------------
  static const text1 = Color(0xFFF5F3EF);
  static const text2 = Color(0xFFA3A09A);
  static const text3 = Color(0xFF6B6863);

  // --- Brand ---------------------------------------------------------------
  static const iris = Color(0xFF7A5CFF); // fallback accent
  static const irisBright = Color(0xFF9E8BFF); // 6.5:1 on ink800
  static const irisDeep = Color(0xFF4B33CC);

  /// The favourite heart. Deliberately fixed: it is an identity signal and
  /// must not drift with the artwork accent.
  static const coral = Color(0xFFFF4D6D);

  /// Radio / live indicator.
  static const amber = Color(0xFFFFB020);

  static const mint = Color(0xFF3DDC97);
  static const danger = Color(0xFFFF5A5A);

  /// Translucent fills for glass chrome. Used only for bars and controls,
  /// never for content surfaces.
  static const glassFill = Color(0x14FFFFFF);
  static const glassStroke = Color(0x29FFFFFF);
}

class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;

  /// The single horizontal page gutter. The old code mixed 16/20/24
  /// depending on the screen.
  static const double gutter = 20;

  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double huge = 56;
}

class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  /// Apple's real squircle, native since Flutter 3.44. Content shapes built
  /// with this match the superellipses the glass chrome draws.
  static RoundedSuperellipseBorder shape(double r) =>
      RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(r));

  static BorderRadius br(double r) => BorderRadius.circular(r);
}

class AppShadows {
  const AppShadows._();

  /// Cards and small raised surfaces.
  static const List<BoxShadow> level1 = [
    BoxShadow(color: Color(0x47000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Media cards, the mini player.
  static const List<BoxShadow> level2 = [
    BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Hero artwork on the player.
  static const List<BoxShadow> level3 = [
    BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 18)),
  ];
}

class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  /// Artwork backdrop cross-fade on the player.
  static const Duration backdrop = Duration(milliseconds: 700);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasised = Curves.easeOutBack;
}
