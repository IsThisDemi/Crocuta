import 'package:flutter/material.dart';

import '../design/spot.dart';
import '../design/tokens.dart';

/// Una scheda con copertina che reagisce al mouse e al tocco sulla sola
/// copertina, non su un riquadro attorno a tutto.
///
/// Prima le schede usavano `InkWell`: al passaggio del mouse si accendeva
/// un rettangolo arrotondato grande quanto copertina e titolo insieme. Sotto
/// una foto tonda d'artista si vedeva un quadrato grigio che con il cerchio
/// non c'entrava niente, e sotto una copertina il riquadro sbordava attorno
/// alle scritte. Apple Music su Mac fa reagire la copertina e basta: un
/// filo piu' grande e piu' luminosa al passaggio, un filo piu' piccola alla
/// pressione.
///
/// [builder] riceve lo stato e decide lui come disegnarlo, perche' solo chi
/// disegna la copertina conosce la sua forma; il resto della scheda resta
/// fermo.
class ArtworkPressable extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget Function(BuildContext context, ArtworkPressState state) builder;

  const ArtworkPressable({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<ArtworkPressable> createState() => _ArtworkPressableState();
}

/// Cosa sta succedendo alla scheda.
@immutable
class ArtworkPressState {
  final bool hovered;
  final bool pressed;

  const ArtworkPressState({required this.hovered, required this.pressed});

  /// La scala da dare alla copertina.
  double get scale => pressed ? 0.97 : (hovered ? 1.025 : 1.0);

  /// Il velo chiaro da stendere sopra la copertina, ritagliato sulla sua
  /// forma.
  double get highlight => hovered && !pressed ? 0.08 : 0.0;
}

class _ArtworkPressableState extends State<ArtworkPressable> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.builder(
          context,
          ArtworkPressState(hovered: _hovered, pressed: _pressed),
        ),
      ),
    );
  }
}

/// La copertina dentro una [ArtworkPressable]: scala e velo animati, sulla
/// forma che le si passa.
class PressableArtwork extends StatelessWidget {
  final ArtworkPressState state;

  /// La forma della copertina, di solito una [SpotBorder] con lo stesso
  /// seme della macchia: il velo chiaro del passaggio del mouse deve
  /// coprire la macchia e basta. Con un raggio d'angolo, come prima, si
  /// accendeva un quadrato arrotondato attorno a una forma che quadrata
  /// non e'.
  final ShapeBorder shape;
  final Widget child;

  const PressableArtwork({
    super.key,
    required this.state,
    required this.shape,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: state.scale,
      duration: AppMotion.fast,
      curve: Curves.easeOutCubic,
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: state.highlight == 0 ? 0 : 1,
                duration: AppMotion.fast,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: shape,
                    color: Colors.white.withValues(alpha: state.highlight),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
