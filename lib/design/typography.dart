import 'package:flutter/material.dart';

import 'tokens.dart';

/// I caratteri: Outfit per titoli e parole grandi, Inter per tutto il
/// resto.
///
/// Outfit e' un grottesco geometrico con le pance quasi tonde e l'occhio
/// alto: tiene la forma dai 22px in su, e le curve rimano con le macchie.
/// Inter fa il lavoro opposto — 11-15px, righe dense — e ha le cifre
/// tabellari che servono al player per i tempi.
///
/// Entrambi variabili, in `assets/fonts/`: niente si scarica all'avvio.
class AppTypography {
  const AppTypography._();

  static const String display = 'Outfit';
  static const String text = 'Inter';

  /// Tabular figures, for durations, positions and counters. Without this the
  /// seek bar timestamps jitter as the digits change width.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle get numeric => TextStyle(
    fontFamily: text,
    fontFeatures: tabular,
    fontWeight: FontWeight.w500,
  );

  static TextTheme textTheme(ColorScheme scheme) {
    TextStyle d(double size, double height, FontWeight w, double tracking) =>
        TextStyle(
          fontFamily: display,
          fontSize: size,
          height: height / size,
          fontWeight: w,
          letterSpacing: tracking,
          color: scheme.onSurface,
        );

    TextStyle t(
      double size,
      double height,
      FontWeight w, {
      double tracking = 0,
      Color? color,
    }) => TextStyle(
      fontFamily: text,
      fontSize: size,
      height: height / size,
      fontWeight: w,
      letterSpacing: tracking,
      color: color ?? scheme.onSurface,
    );

    return TextTheme(
      displayLarge: d(48, 48, FontWeight.w700, -0.8),
      displayMedium: d(40, 42, FontWeight.w700, -0.6),
      displaySmall: d(34, 36, FontWeight.w700, -0.4),
      headlineLarge: d(36, 38, FontWeight.w700, -0.5),
      headlineMedium: d(30, 32, FontWeight.w700, -0.4),
      headlineSmall: d(24, 27, FontWeight.w700, -0.2),
      titleLarge: d(20, 24, FontWeight.w600, 0),
      titleMedium: t(15.5, 20, FontWeight.w600),
      titleSmall: t(14, 18, FontWeight.w600),
      bodyLarge: t(15, 21, FontWeight.w400),
      bodyMedium: t(13.5, 19, FontWeight.w400, color: AppColors.text2),
      bodySmall: t(12, 16, FontWeight.w400, color: AppColors.text2),
      labelLarge: t(14, 18, FontWeight.w600),
      labelMedium: t(12, 16, FontWeight.w600, tracking: 0.1),
      labelSmall: t(
        11,
        14,
        FontWeight.w600,
        tracking: 0.2,
        color: AppColors.text2,
      ),
    );
  }
}
