import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import 'liquid.dart';

/// La cornice delle pagine di un disco o di una playlist.
///
/// Nessuna barra in cima, come nella pagina artista e come in Apple Music:
/// una barra, anche di vetro, e' una riga stesa sopra la copertina che
/// ripeteva "Album" sopra un album. Resta il solo tasto indietro, e il
/// titolo compare nella riga in alto quando la copertina e' scorsa via —
/// quello lo disegna [MediaDetailPage], che sa dov'e' il titolo grande.
class DetailScaffold extends StatelessWidget {
  final Widget body;

  /// Pulsanti di vetro in alto a destra, di fronte al tasto indietro.
  final List<Widget> actions;

  const DetailScaffold({
    super.key,
    required this.body,
    this.actions = const [],
  });

  /// Di quanto il tasto indietro sta sotto l'area sicura.
  static const double backButtonOffset = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: const Wallpaper(),
      statusBarStyle: GlassStatusBarStyle.light,
      topEdgeFade: false,
      bodyOverlays: [
        Positioned(
          left: AppSpacing.gutter,
          top:
              MediaQuery.paddingOf(context).top +
              backButtonOffset +
              topWindowInset(context),
          child: GlassCircleIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        if (actions.isNotEmpty)
          Positioned(
            right: AppSpacing.gutter,
            top:
                MediaQuery.paddingOf(context).top +
                backButtonOffset +
                topWindowInset(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.xs,
              children: actions,
            ),
          ),
      ],
      body: Material(
        type: MaterialType.transparency,
        child: StatusBarScrim(child: body),
      ),
    );
  }
}

/// Il nero sotto l'orologio, che compare quando la pagina scorre.
///
/// A pagina ferma non c'e': le testate (la foto dell'artista, la copertina)
/// devono arrivare fino al bordo dello schermo. Appena si scorre, il nero
/// della pagina sale sotto la barra di stato, come sotto i titoli piccoli,
/// e le righe non passano piu' sotto l'ora. Solo dove c'e' una barra di
/// stato ([hasStatusBarFade]).
class StatusBarScrim extends StatefulWidget {
  final Widget child;

  const StatusBarScrim({super.key, required this.child});

  @override
  State<StatusBarScrim> createState() => _StatusBarScrimState();
}

class _StatusBarScrimState extends State<StatusBarScrim> {
  final _shown = ValueNotifier(0.0);

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.depth == 0) {
      _shown.value = (n.metrics.pixels / 40).clamp(0.0, 1.0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasStatusBarFade) return widget.child;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top + AppSpacing.lg,
          child: IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: _shown,
              builder: (context, v, child) => Opacity(opacity: v, child: child),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.ink900,
                      Color(0xE6000000),
                      Color(0x00000000),
                    ],
                    stops: [0, 0.6, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
