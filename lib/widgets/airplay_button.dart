import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_theme.dart';
import 'liquid.dart';
import '../dev/readme_shots.dart';

/// Il pulsante AirPlay di sistema, vestito come gli altri cerchi del player.
///
/// Lo sfondo lo disegna Flutter, uguale ai vicini; sopra c'e'
/// `AVRoutePickerView`, il pulsante di Apple, che apre il suo pannello per
/// scegliere dove suonare. Cambia l'uscita audio dell'app intera, quindi
/// anche quella di libmpv, e non chiede nessuna autorizzazione.
///
/// Solo su iOS e macOS: altrove non c'e' AirPlay, e il pulsante non compare.
class AirPlayButton extends StatelessWidget {
  final double size;

  /// Senza il cerchio di vetro: nella fila in fondo al player i vicini
  /// sono icone nude, e un cerchio solo spiccava.
  final bool bare;

  /// Il colore del simbolo a riposo; di norma bianco spento.
  final Color? tint;

  const AirPlayButton({
    super.key,
    this.size = 38,
    this.bare = false,
    this.tint,
  });

  static const _viewType = 'crocuta/route_picker';

  static bool get isAvailable {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    // Nei test non c'e' chi ospiti la platform view; nelle foto del README
    // la vista di sistema non verrebbe fotografata, e il tasto uscirebbe
    // vuoto: in entrambi i casi si disegna l'icona.
    if (readmeShotsEnabled) return false;
    return !Platform.environment.containsKey('FLUTTER_TEST');
  }

  /// Se la piattaforma ha AirPlay. Chi dispone il pulsante lo usa per non
  /// lasciare uno spazio vuoto dove il pulsante non c'e'.
  static bool get isSupported => Platform.isIOS || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();

    final params = <String, dynamic>{
      'tint': (tint ?? Colors.white.withValues(alpha: 0.7)).toARGB32(),
      'activeTint': context.colors.accent.toARGB32(),
    };
    final icon = size * 0.62;

    return Tooltip(
      message: 'AirPlay',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Il cerchio, come i vicini. Senza tocco: il tocco lo prende il
            // pulsante di sistema sopra.
            if (!bare)
              IgnorePointer(
                child: GlassCircleIconButton(
                  native: false,
                  size: size,
                  icon: Icons.circle,
                  iconColor: Colors.transparent,
                ),
              ),
            SizedBox.square(
              dimension: icon,
              child: isAvailable
                  ? (Platform.isIOS
                        ? UiKitView(
                            viewType: _viewType,
                            creationParams: params,
                            creationParamsCodec: const StandardMessageCodec(),
                          )
                        : AppKitView(
                            viewType: _viewType,
                            creationParams: params,
                            creationParamsCodec: const StandardMessageCodec(),
                          ))
                  : Icon(
                      Icons.airplay_rounded,
                      size: icon,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
