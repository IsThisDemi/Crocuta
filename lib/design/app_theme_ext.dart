import 'package:flutter/material.dart';

import 'tokens.dart';

/// App colours that Material's [ColorScheme] has no slot for.
///
/// Carried on [ThemeData.extensions] so a widget can read them with
/// `context.colors.favorite` instead of writing a hex literal inline.
@immutable
class AppColorsExt extends ThemeExtension<AppColorsExt> {
  /// The live accent, derived from the current track's artwork (or the brand
  /// iris when the artwork yields nothing readable).
  final Color accent;

  /// L'accento spento, per il testo secondario che deve portare il colore
  /// del brano senza gridare: il nome dell'artista sotto il titolo, le
  /// parole inattive della navigazione. In Macchia era l'ocra del manto.
  final Color accentMuted;

  /// Always coral, never the artwork accent: the heart is an identity signal.
  final Color favorite;

  /// Radio / live indicator.
  final Color radio;

  final Color positive;
  final Color danger;

  /// Text ramp.
  final Color textStrong;
  final Color textMuted;
  final Color textFaint;

  /// Translucent fills for glass chrome only.
  final Color glassFill;
  final Color glassStroke;

  const AppColorsExt({
    required this.accent,
    required this.accentMuted,
    required this.favorite,
    required this.radio,
    required this.positive,
    required this.danger,
    required this.textStrong,
    required this.textMuted,
    required this.textFaint,
    required this.glassFill,
    required this.glassStroke,
  });

  factory AppColorsExt.standard({Color accent = AppColors.irisBright}) =>
      AppColorsExt(
        accent: accent,
        accentMuted: muteAccent(accent),
        favorite: AppColors.coral,
        radio: AppColors.amber,
        positive: AppColors.mint,
        danger: AppColors.danger,
        textStrong: AppColors.text1,
        textMuted: AppColors.text2,
        textFaint: AppColors.text3,
        glassFill: AppColors.glassFill,
        glassStroke: AppColors.glassStroke,
      );

  @override
  AppColorsExt copyWith({
    Color? accent,
    Color? accentMuted,
    Color? favorite,
    Color? radio,
    Color? positive,
    Color? danger,
    Color? textStrong,
    Color? textMuted,
    Color? textFaint,
    Color? glassFill,
    Color? glassStroke,
  }) {
    return AppColorsExt(
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      favorite: favorite ?? this.favorite,
      radio: radio ?? this.radio,
      positive: positive ?? this.positive,
      danger: danger ?? this.danger,
      textStrong: textStrong ?? this.textStrong,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      glassFill: glassFill ?? this.glassFill,
      glassStroke: glassStroke ?? this.glassStroke,
    );
  }

  @override
  AppColorsExt lerp(ThemeExtension<AppColorsExt>? other, double t) {
    if (other is! AppColorsExt) return this;
    return AppColorsExt(
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      favorite: Color.lerp(favorite, other.favorite, t)!,
      radio: Color.lerp(radio, other.radio, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
    );
  }
}

/// L'accento portato verso il grigio del testo secondario: resta leggibile
/// sul nero (e' a meta' strada fra due colori che lo sono) ma si capisce di
/// che colore e' il brano.
Color muteAccent(Color accent) => Color.lerp(AppColors.text2, accent, 0.6)!;

extension AppThemeContext on BuildContext {
  /// App-specific colours: `context.colors.favorite`.
  AppColorsExt get colors =>
      Theme.of(this).extension<AppColorsExt>() ?? AppColorsExt.standard();

  /// Shorthand for the Material scheme and text styles.
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}
