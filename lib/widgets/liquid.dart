import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/app_theme.dart';
import '../design/spot.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Plain black background. The user wants a simple black canvas everywhere
/// except the player, which derives its colors from the cover art.
class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF000000));
  }
}

/// Background used by screens: the aurora wallpaper under [child].
class LiquidBackground extends StatelessWidget {
  final Widget child;

  const LiquidBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [const Wallpaper(), child]);
  }
}

/// Frosted-glass surface built on the real Liquid Glass shader (iOS 26).
///
/// Apple reserves glass for the control/navigation layer; content stays
/// opaque. Use this for bars, pills and cards — not for every list row.
class Glass extends StatelessWidget {
  /// Defaults, named so `build` can tell "untouched" from "customised".
  static const double _defaultBlur = 14;
  static const double _defaultElevation = 1;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  final Color? tint;
  final Color? borderColor;
  final VoidCallback? onTap;
  final BoxConstraints? constraints;
  final bool squircle;
  final double elevation;

  const Glass({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.radius = 24,
    this.blur = _defaultBlur,
    this.tint,
    this.borderColor,
    this.onTap,
    this.constraints,
    this.squircle = true,
    this.elevation = _defaultElevation,
  });

  @override
  Widget build(BuildContext context) {
    final shape = squircle
        ? LiquidRoundedSuperellipse(borderRadius: radius)
        : LiquidRoundedRectangle(borderRadius: radius);

    // In grouped mode the package ignores per-widget `settings` unless the
    // widget owns its layer, and warns about it. So: say nothing and inherit
    // the app-wide glass theme (the normal case), and only claim a private
    // layer when this instance genuinely asks for something different.
    final customised =
        tint != null || blur != _defaultBlur || elevation != _defaultElevation;

    final surface = GlassContainer(
      shape: shape,
      margin: margin,
      padding: padding,
      quality: GlassQuality.standard,
      useOwnLayer: customised,
      settings: customised
          ? LiquidGlassSettings(
              blur: blur,
              glassColor: tint ?? const Color(0x0AFFFFFF),
              standardOpacityMultiplier: 0.65,
              whitenStrength: 0.08,
              shadowElevation: elevation,
            )
          : null,
      child: child,
    );

    if (onTap == null) {
      return constraints == null
          ? surface
          : Container(constraints: constraints, child: surface);
    }
    return GestureDetector(
      onTap: onTap,
      child: constraints == null
          ? surface
          : Container(constraints: constraints, child: surface),
    );
  }
}

/// Glass pill button (Apple-style control).
class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double radius;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: radius,
      onTap: onPressed,
      blur: 12,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: child,
    );
  }
}

/// Circular glass icon button, like iOS Control Center buttons.
class GlassCircleIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? iconColor;
  final Color? background;

  /// Queste icone da sole non si spiegano: senza etichetta nessuno indovina
  /// cosa sia il crossfade o la radio.
  final String? tooltip;

  /// Vetro di sistema invece di quello disegnato da Flutter.
  ///
  /// Di norma si': tab bar, brano in riproduzione e barre in alto sono tutti
  /// `NativeGlass`, e un tasto indietro fatto con lo shader del pacchetto
  /// accanto a loro si legge come un materiale diverso — piu' piatto, con
  /// un bordo suo. E' la stessa ragione per cui quelle barre esistono al
  /// posto di quelle del pacchetto.
  ///
  /// `false` solo per i tasti che stanno dentro una lista che scorre: ogni
  /// vetro di sistema e' una platform view, e spostarne mezza dozzina a
  /// ogni fotogramma su iPhone e' un costo che la schermata in
  /// riproduzione, appena liberata dagli scatti, non deve riprendersi.
  final bool native;

  const GlassCircleIconButton({
    this.tooltip,
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconColor,
    this.background,
    this.native = true,
  });

  @override
  State<GlassCircleIconButton> createState() => _GlassCircleIconButtonState();
}

/// In Macchia il tasto tondo e' una macchia scura: indietro, statistiche,
/// impostazioni sono comandi come il play, solo spenti. Col mouse sopra si
/// accende del colore del brano, con l'icona nera, come il play. La forma
/// dipende dall'icona: lo stesso comando ha sempre la stessa macchia.
class _GlassCircleIconButtonState extends State<GlassCircleIconButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final colors = context.colors;
    final lit = _hover && w.onPressed != null;
    final shape = SpotBorder(seed: 'icon-${w.icon.codePoint}', wobble: 0.75);
    final button = Semantics(
      button: true,
      enabled: w.onPressed != null,
      child: MouseRegion(
        cursor: w.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: w.onPressed,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: AnimatedScale(
            scale: _down ? 0.9 : 1,
            duration: AppMotion.fast,
            child: SpotMotionBuilder(
              builder: (context, t) => Container(
                width: w.size,
                height: w.size,
                decoration: ShapeDecoration(
                  color: lit
                      ? colors.accent
                      : (w.background ?? AppColors.ink600),
                  shape: shape.copyWith(
                    time: t,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: lit ? 0 : 0.08),
                    ),
                  ),
                ),
                child: Icon(
                  w.icon,
                  size: w.size * 0.46,
                  color: lit ? AppColors.ink900 : (w.iconColor ?? Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (w.tooltip == null) return button;
    return Tooltip(message: w.tooltip!, child: button);
  }
}

/// The classic Apple Music solid-white play/pause button.
class SolidPlayButton extends StatelessWidget {
  final bool isLoading;
  final bool isPlaying;
  final VoidCallback? onPressed;

  const SolidPlayButton({
    super.key,
    required this.isLoading,
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SizedBox(
            width: 76,
            height: 76,
            child: Icon(
              isLoading
                  ? Icons.hourglass_top
                  : isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 44,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
