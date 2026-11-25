import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_theme_ext.dart';
import 'tokens.dart';
import 'typography.dart';
import 'motion.dart';

export 'app_theme_ext.dart';
export 'tokens.dart';
export 'typography.dart';

/// The app's Material theme.
///
/// [accent] is the live artwork-derived accent; it defaults to the brand
/// iris when no artwork colour is available or readable.
ThemeData buildAppTheme({Color accent = AppColors.irisBright}) {
  final scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: AppColors.ink900,
    primaryContainer: AppColors.irisDeep,
    onPrimaryContainer: AppColors.text1,
    secondary: AppColors.coral,
    onSecondary: AppColors.ink900,
    tertiary: AppColors.mint,
    onTertiary: AppColors.ink900,
    // Opaque, unlike the old 0x1AFFFFFF. A translucent surface here made
    // every dialog, menu and card composite white over its backdrop.
    surface: AppColors.ink800,
    onSurface: AppColors.text1,
    surfaceContainerLowest: AppColors.ink900,
    surfaceContainerLow: AppColors.ink800,
    surfaceContainer: AppColors.ink700,
    surfaceContainerHigh: AppColors.ink600,
    surfaceContainerHighest: AppColors.ink500,
    onSurfaceVariant: AppColors.text2,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    error: AppColors.danger,
    onError: AppColors.ink900,
  );

  final texts = AppTypography.textTheme(scheme);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    textTheme: texts,
    fontFamily: AppTypography.text,
    scaffoldBackgroundColor: AppColors.ink900,
    canvasColor: AppColors.ink900,
    splashFactory: InkSparkle.splashFactory,
    extensions: [AppColorsExt.standard(accent: accent)],

    // Su iPhone lo scorrimento di iOS, col gesto per tornare indietro; sul
    // Mac e su Windows una dissolvenza breve, come le app Apple per Mac.
    // Prima non c'era niente e ogni piattaforma prendeva il suo default:
    // sul Mac lo scorrimento di iOS su tutta la larghezza della finestra.
    // Macchia: le pagine nuove si aprono dentro una macchia che parte dal
    // punto toccato (vedi SpotPageTransitionsBuilder), su ogni piattaforma.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: SpotPageTransitionsBuilder(),
        TargetPlatform.android: SpotPageTransitionsBuilder(),
        TargetPlatform.macOS: SpotPageTransitionsBuilder(),
        TargetPlatform.windows: SpotPageTransitionsBuilder(),
        TargetPlatform.linux: SpotPageTransitionsBuilder(),
      },
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.text1,
      titleTextStyle: texts.titleLarge,
    ),

    // Dialogs used to hardcode Color(0xFF1C1C1E) at three call sites.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.ink600,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: AppRadius.shape(AppRadius.xl),
      titleTextStyle: texts.titleLarge,
      contentTextStyle: texts.bodyLarge,
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.ink600,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: AppRadius.shape(AppRadius.md),
      textStyle: texts.bodyLarge,
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.ink700,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: AppColors.outline,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),

    cardTheme: CardThemeData(
      color: AppColors.ink700,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: AppRadius.shape(AppRadius.md),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: AppColors.ink900,
        textStyle: texts.labelLarge,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        shape: AppRadius.shape(AppRadius.pill),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.ink600,
        foregroundColor: AppColors.text1,
        elevation: 0,
        textStyle: texts.labelLarge,
        shape: AppRadius.shape(AppRadius.pill),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: texts.labelLarge,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.text1),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.ink700,
      selectedColor: accent,
      side: const BorderSide(color: AppColors.outlineVariant),
      labelStyle: texts.labelMedium,
      shape: AppRadius.shape(AppRadius.pill),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.ink500,
      hintStyle: texts.bodyLarge?.copyWith(color: AppColors.text3),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: AppRadius.br(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.br(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.br(AppRadius.md),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: AppColors.ink500,
      thumbColor: AppColors.text1,
      overlayColor: accent.withValues(alpha: 0.16),
      trackHeight: 4,
      valueIndicatorColor: AppColors.ink600,
    ),

    listTileTheme: ListTileThemeData(
      iconColor: AppColors.text2,
      textColor: AppColors.text1,
      titleTextStyle: texts.titleMedium,
      subtitleTextStyle: texts.bodySmall,
      shape: AppRadius.shape(AppRadius.sm),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.outlineVariant,
      thickness: 0.6,
      space: 0.6,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink600,
      contentTextStyle: texts.bodyLarge,
      elevation: 0,
      shape: AppRadius.shape(AppRadius.md),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink600,
        borderRadius: AppRadius.br(AppRadius.xs),
      ),
      textStyle: texts.bodySmall?.copyWith(color: AppColors.text1),
    ),

    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.35),
      selectionHandleColor: accent,
    ),

    // Desktop hygiene the app had none of.
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        AppColors.text3.withValues(alpha: 0.6),
      ),
      radius: const Radius.circular(AppRadius.xs),
      thickness: const WidgetStatePropertyAll(7),
    ),

    iconTheme: const IconThemeData(color: AppColors.text1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
  );
}

/// Theme for the shader-based glass chrome (bars and controls only).
///
/// Two deliberate departures from the package defaults:
///
/// 1. **Neutral glow.** `GlassGlowColors.fallback` leaves `primary` null on
///    purpose so the package can resolve "a brightness-aware warm specular
///    highlight" at runtime. That warm highlight is what previously read as
///    yellow underlines beneath the tab bar, and is why the tab bar and mini
///    player had opted out of glass entirely. Setting an explicit neutral
///    primary removes it at the source.
///
/// 2. **More tinted, darker edged.** iOS 26's very clear glass was walked
///    back in iOS 27 towards a more tinted default with darkened edges and
///    brighter speculars — it is the dark edge that makes a bar read as
///    floating above content rather than dissolving into it. Chromatic
///    aberration is kept low because the rim dispersion is what breaks up
///    into colour fringes on small pill-shaped surfaces.
GlassThemeData buildGlassTheme({Color accent = AppColors.irisBright}) {
  final variant = GlassThemeVariant(
    settings: const GlassThemeSettings(
      // Sfocatura piu' marcata: a 18 la barra leggeva come un semplice velo
      // traslucido, con il contenuto sottostante ancora nitido.
      blur: 32,
      thickness: 14,
      glassColor: Color(0x1FFFFFFF),
      visibility: 0.62,
      chromaticAberration: 0.25,
      lightIntensity: 1.1,
    ),
    quality: GlassQuality.standard,
    glowColors: GlassGlowColors(
      primary: Colors.white.withValues(alpha: 0.22),
      glowBlurRadius: 8,
      glowOpacity: 0.45,
    ),
  );
  return GlassThemeData(light: variant, dark: variant);
}
