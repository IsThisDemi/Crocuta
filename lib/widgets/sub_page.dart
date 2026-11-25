import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../widgets/content_width.dart';
import 'app_background.dart';
import 'detail_scaffold.dart';
import 'large_title.dart';
import 'liquid.dart';
import 'native_glass.dart';

/// Chrome for a screen pushed inside a tab's navigator.
///
/// Lo stesso schema delle altre pagine: il tasto indietro di vetro tondo in
/// alto a sinistra, il titolo grande in cima al contenuto, e scorrendo il
/// titolo piccolo che compare nella riga del tasto. Prima queste pagine
/// avevano una barra di vetro larga tutta la finestra — su un Mac 1360 px
/// per una colonna di contenuto da 1100 — mentre Home, Libreria, Stats e
/// le pagine di album e artista avevano gia' il titolo grande: due modi di
/// dire "dove sei" nella stessa app.
///
/// Il titolo grande deve scorrere via insieme al contenuto, ma il contenuto
/// e' di ogni pagina il suo (una lista, una griglia, una colonna con una
/// lista dentro, uno stato vuoto). Invece di chiedere a ognuna di mettersi
/// il titolo in testa, qui c'e' un [NestedScrollView]: il titolo sta
/// nell'intestazione che scorre, e la lista della pagina continua da li'.
///
/// Nothing here draws a mini player or a tab bar: those live once, in the
/// shell, and stay put while routes come and go.
class SubPage extends StatelessWidget {
  final Widget child;

  /// Il titolo grande. Senza, la pagina comincia sotto il tasto indietro.
  final String? title;

  /// Comandi in alto a destra, di fronte al tasto indietro, dentro una
  /// capsula di vetro.
  final List<Widget> actions;

  /// La larghezza della colonna, che e' anche quella del titolo: una pagina
  /// stretta come le impostazioni deve avere il titolo allineato alle sue
  /// righe, non al bordo di una colonna piu' larga che non si vede.
  final double maxWidth;

  const SubPage({
    super.key,
    required this.child,
    this.title,
    this.actions = const [],
    this.maxWidth = ContentWidth.wide,
  });

  @override
  Widget build(BuildContext context) {
    final buttonTop =
        MediaQuery.paddingOf(context).top +
        DetailScaffold.backButtonOffset +
        topWindowInset(context);
    final hasTitle = title != null && title!.isNotEmpty;

    // Il margine per i semafori della finestra lo mette gia' questa pagina,
    // nell'intestazione: il figlio non deve rimetterlo, o le schermate che
    // sono anche radici di un tab — la coda — lo conterebbero due volte.
    final content = TopInsetApplied(child: WindowInsetApplied(child: child));

    final Widget body;
    if (!hasTitle) {
      body = ContentWidth(
        maxWidth: maxWidth,
        child: Padding(
          padding: EdgeInsets.only(top: topBarInset(context)),
          child: content,
        ),
      );
    } else {
      body = CollapsingTitleFrame(
        title: title!,
        barOffset: DetailScaffold.backButtonOffset,
        child: ContentWidth(
          maxWidth: maxWidth,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    topBarInset(context) - AppSpacing.md,
                    AppSpacing.gutter,
                    AppSpacing.xs,
                  ),
                  child: LargeTitle(title!, maxLines: 2),
                ),
              ),
            ],
            // La lista della pagina deve prendere il controller che il
            // NestedScrollView le passa, altrimenti titolo e lista scorrono
            // ognuno per conto suo. Lo prende da sola solo su iOS e
            // Android: sul Mac Flutter non fa ereditare il controller
            // primario, e lo si chiede qui per tutte le piattaforme.
            body: Builder(
              builder: (context) => PrimaryScrollController(
                controller: PrimaryScrollController.of(context),
                automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
                child: content,
              ),
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      background: const AppBackground(),
      statusBarStyle: GlassStatusBarStyle.light,
      topEdgeFade: hasStatusBarFade,
      topEdgeFadeExtent: statusBarOnlyFade,
      bodyOverlays: [
        Positioned(
          left: AppSpacing.gutter,
          top: buttonTop,
          child: GlassCircleIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        if (actions.isNotEmpty)
          Positioned(
            right: AppSpacing.gutter,
            top: buttonTop,
            child: GlassActions(actions: actions),
          ),
      ],
      body: Material(type: MaterialType.transparency, child: body),
    );
  }
}

/// I comandi di una pagina dentro una capsula di vetro, alta quanto il
/// tasto indietro che le sta di fronte.
///
/// Una capsula e non un cerchio per comando: i comandi di queste pagine
/// sono di forme diverse (un'icona, un testo, un interruttore), e il
/// contenitore comune li fa leggere come un gruppo solo, come la capsula
/// dei comandi in alto a destra di iOS 26.
class GlassActions extends StatelessWidget {
  final List<Widget> actions;

  const GlassActions({super.key, required this.actions});

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          Positioned.fill(
            child: NativeGlass(
              capsule: true,
              radius: _height / 2,
              opacity: 0.72,
              fallback: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ink700.withValues(alpha: 0.78),
                  borderRadius: AppRadius.br(AppRadius.pill),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ],
      ),
    );
  }
}
