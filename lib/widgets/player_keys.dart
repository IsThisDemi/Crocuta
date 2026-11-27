import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import 'airplay_button.dart';

// I comandi del player, condivisi col videoclip (screens/video_screen.dart):
// le macchioline della fila in fondo e i glifi grandi accanto al play.

/// Un comando della fila in fondo al player: una macchiolina viva.
class PlayerKey extends StatefulWidget {
  final IconData? icon;
  final String label;
  final String? tooltip;
  final bool active;
  final VoidCallback? onTap;
  final bool airplay;

  const PlayerKey({
    super.key,
    required IconData this.icon,
    required this.label,
    required VoidCallback this.onTap,
    this.active = false,
    this.tooltip,
  }) : airplay = false;

  /// L'uscita audio: il pulsante e' quello di sistema, che apre il suo
  /// selettore; qui gli si da' la stessa macchia e lo stesso nome.
  const PlayerKey.airplay({super.key})
    : icon = null,
      label = 'AirPlay',
      tooltip = null,
      active = false,
      onTap = null,
      airplay = true;

  @override
  State<PlayerKey> createState() => _PlayerKeyState();
}

class _PlayerKeyState extends State<PlayerKey> {
  bool _hover = false;
  bool _down = false;

  static const double _size = 42;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final w = widget;
    final lit = w.active;
    final iconColor = lit ? AppColors.ink900 : colors.accent;
    final fill = lit
        ? colors.accent
        : Colors.white.withValues(alpha: _hover ? 0.12 : 0.07);

    final spot = SpotMotionBuilder(
      builder: (context, t) => AnimatedContainer(
        duration: AppMotion.fast,
        width: _size,
        height: _size,
        decoration: ShapeDecoration(
          color: fill,
          shape: SpotBorder(
            seed: 'pane-${w.label}',
            wobble: 0.8,
            time: t,
            music: SpotMotion.musicOf(context),
          ),
        ),
        alignment: Alignment.center,
        child: w.airplay
            ? AirPlayButton(size: _size, bare: true, tint: colors.accent)
            : Icon(w.icon, size: 22, color: iconColor),
      ),
    );

    // Solo la macchia: il nome sta nel suggerimento col mouse sopra.
    final body = AnimatedScale(
      scale: _down ? 0.9 : (_hover ? 1.06 : 1),
      duration: AppMotion.fast,
      child: spot,
    );

    return Tooltip(
      message: w.tooltip ?? w.label,
      child: Semantics(
        button: true,
        selected: lit,
        label: w.label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: SizedBox(
            width: 52,
            // AirPlay: il tocco lo prende la vista di sistema dentro la
            // macchia, non un GestureDetector sopra.
            child: w.airplay
                ? body
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => setState(() => _down = true),
                    onTapCancel: () => setState(() => _down = false),
                    onTapUp: (_) => setState(() => _down = false),
                    onTap: w.onTap,
                    child: body,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Precedente e successivo: un glifo grande e nudo, come in Apple Music.
/// Premuto si stringe un poco; col mouse sopra gli compare dietro lo stesso
/// alone degli interruttori.
class PlayerGlyph extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const PlayerGlyph({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<PlayerGlyph> createState() => _PlayerGlyphState();
}

class _PlayerGlyphState extends State<PlayerGlyph> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _down ? 0.86 : 1,
              duration: AppMotion.fast,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: _hover ? 0.08 : 0),
                ),
                child: Icon(widget.icon, size: 44, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
