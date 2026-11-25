import 'package:flutter/material.dart';

import 'spot.dart';

/// Tutti i testi dell'app che crescono sui colpi della musica, come le
/// macchie: un'opzione per ridere, spenta di serie (Impostazioni → Pulsing
/// Text).
///
/// Cambia la scala del testo del [MediaQuery] sotto di se', quindi ogni
/// testo si rimpagina a ogni colpo e le righe si allargano davvero: e' il
/// punto. Si ricostruiscono solo i widget che leggono la scala del testo,
/// e solo quando cambia di almeno mezzo punto percentuale.
class TextPulse extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const TextPulse({super.key, required this.enabled, required this.child});

  /// Di quanto cresce il testo al colpo pieno di basso, e a quello di
  /// rullante.
  static const double bass = 0.14, snap = 0.04;

  static double factorFor(SpotMusic m) {
    final k =
        1 + bass * m.pulse.clamp(0.0, 2.0) + snap * m.snap.clamp(0.0, 2.0);
    return (k * 200).round() / 200;
  }

  @override
  Widget build(BuildContext context) {
    // Sempre gli stessi widget, acceso o spento: un livello in piu' o in
    // meno ricreerebbe tutto cio' che sta sotto, navigatore compreso, e
    // accenderlo nelle Impostazioni ti porterebbe fuori dalla pagina.
    final music = SpotMotion.musicListenableOf(context) ?? _silence;
    return ValueListenableBuilder<SpotMusic>(
      valueListenable: music,
      child: child,
      builder: (context, m, child) {
        final mq = MediaQuery.of(context);
        final k = enabled ? factorFor(m) : 1.0;
        return MediaQuery(
          data: k == 1
              ? mq
              : mq.copyWith(textScaler: _PulseScaler(mq.textScaler, k)),
          child: child!,
        );
      },
    );
  }

  static final _silence = ValueNotifier<SpotMusic>(silentMusic);
}

class _PulseScaler extends TextScaler {
  final TextScaler base;
  final double k;

  const _PulseScaler(this.base, this.k);

  @override
  double scale(double fontSize) => base.scale(fontSize) * k;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * k;

  @override
  bool operator ==(Object other) =>
      other is _PulseScaler && other.base == base && other.k == k;

  @override
  int get hashCode => Object.hash(base, k);
}
