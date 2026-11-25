import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'app_theme.dart';

/// Turns a raw artwork colour into one that is safe to use in the foreground.
///
/// `dominantColorOf` deliberately biases towards dark, saturated tones,
/// which is right for a blurred backdrop and wrong for an accent that has to
/// sit on text, sliders and icons. This pulls it into a usable band and then
/// refuses it outright if it still would not read.
Color toneMapAccent(Color? raw) {
  if (raw == null) return AppColors.irisBright;

  final hsl = HSLColor.fromColor(raw);

  // Una copertina senza tinta non ne ha una da prestare: alzare la
  // saturazione a 0.35 su un grigio se la inventa, e un grigio neutro
  // usciva rosa polveroso. Si restituisce un grigio chiaro, che dice
  // "questa copertina non ha colore" invece del viola di marca, che dice
  // "colore a caso".
  if (hsl.saturation < 0.15) return _neutralAccent;

  final mapped = hsl
      .withSaturation(hsl.saturation.clamp(0.35, 0.85))
      .withLightness(hsl.lightness.clamp(0.55, 0.72));

  // Schiarire, non scartare. A parita' di lightness HSL un blu ha
  // luminanza relativa molto piu' bassa di un rosso (0.0722 contro
  // 0.2126), quindi non arrivava a 4.5:1 e veniva buttato via: una
  // copertina blu finiva sul viola di marca pur avendo una tinta
  // perfettamente usabile. Alzando la lightness il contrasto sale sempre.
  var out = mapped;
  while (_contrast(out.toColor(), AppColors.ink800) < 4.5 &&
      out.lightness < 0.92) {
    out = out.withLightness((out.lightness + 0.03).clamp(0.0, 0.92));
  }

  return _contrast(out.toColor(), AppColors.ink800) >= 4.5
      ? out.toColor()
      : _neutralAccent;
}

/// L'accento per una copertina che non ha colore.
const _neutralAccent = Color(0xFFD5D5DE);

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

  // Color.r/g/b are already 0-1 in the current Flutter API.
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Il contrasto di un colore contro la tela dell'app. Esposto per i test:
/// e' l'invariante che il tone mapping deve garantire.
double contrastOnCanvas(Color c) => _contrast(c, AppColors.ink800);

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The accent for a specific piece of artwork.
final artworkAccentProvider = FutureProvider.autoDispose.family<Color, String>((
  ref,
  url,
) async {
  if (url.isEmpty) return AppColors.irisBright;
  final raw = await ref.watch(vividColorProvider(url).future);
  return toneMapAccent(raw);
});

/// Re-themes its subtree around the colour of [artworkUrl].
///
/// Apple Music lets an artist or album page take its colour from its own
/// image rather than from whatever happens to be playing, so this is scoped
/// per page instead of being global. It sits below `MaterialApp`: putting it
/// above would rebuild every route on each track change.
class AccentScope extends ConsumerWidget {
  final String? artworkUrl;
  final Widget child;

  /// Un accento deciso da chi chiama, al posto di quello della copertina:
  /// serve alle raccolte che una copertina vera non ce l'hanno.
  final Color? color;

  const AccentScope({
    super.key,
    required this.artworkUrl,
    required this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = artworkUrl;
    final accent = color != null
        ? color!
        : (url == null || url.isEmpty)
        ? AppColors.irisBright
        : ref
              .watch(artworkAccentProvider(url))
              .maybeWhen(data: (c) => c, orElse: () => AppColors.irisBright);

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: AppMotion.slow,
      curve: AppMotion.standard,
      builder: (context, value, child) {
        final c = value ?? accent;
        // Si ricostruisce il tema intero invece di rattoppare colorScheme.
        // Sotto-temi come filledButtonTheme si portano il colore cotto
        // dentro: con il solo copyWith i bottoni restavano del viola di
        // partenza mentre il resto della pagina virava al colore della
        // copertina, lasciando due accenti diversi nella stessa schermata.
        return Theme(
          data: buildAppTheme(accent: c),
          child: child!,
        );
      },
      child: child,
    );
  }
}
