import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'spot.dart';

/// Il movimento dell'app, sul modello di quello di Apple.
///
/// Apple anima quasi tutto con molle, non con curve a durata fissa: una
/// molla parte con la velocita' del gesto, rallenta come un oggetto vero e
/// si posa. Le curve fisse di prima — 400 ms per aprire il player, 220 per
/// chiuderlo, qualunque fosse il gesto — erano la ragione per cui tutto
/// sembrava legnoso.

/// Una molla come quelle di SwiftUI, `spring(duration:bounce:)`, usata come
/// curva: per le transizioni delle route, che vogliono una curva e una
/// durata. [settle] e' il tempo in cui la molla si posa davvero.
class SpringCurve extends Curve {
  final SpringSimulation _sim;
  final double _settle;

  // ignore: prefer_const_constructors_in_immutables
  SpringCurve._(this._sim, this._settle);

  factory SpringCurve({
    Duration duration = const Duration(milliseconds: 500),
    double bounce = 0,
  }) {
    final spring = SpringDescription.withDurationAndBounce(
      duration: duration,
      bounce: bounce,
    );
    final sim = SpringSimulation(
      spring,
      0,
      1,
      0,
      tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
    );
    var t = 0.0;
    while (!sim.isDone(t) && t < 3) {
      t += 1 / 240;
    }
    return SpringCurve._(sim, t);
  }

  /// Quanto dura la transizione che usa questa curva.
  Duration get settle => Duration(microseconds: (_settle * 1e6).round());

  @override
  double transformInternal(double t) => _sim.x(t * _settle);
}

/// Le molle dell'app.
abstract final class AppSprings {
  /// Il player che sale, un foglio che si apre: veloce, senza rimbalzo,
  /// come le schede modali di iOS.
  static final present = SpringCurve(
    duration: const Duration(milliseconds: 460),
  );

  /// Quando si chiude: un filo piu' rapido, come in iOS.
  static final dismiss = SpringCurve(
    duration: const Duration(milliseconds: 380),
  );

  /// La molla di un pannello lasciato col dito: parte dalla sua velocita'.
  static final drag = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 420),
  );
}

/// Quanto il player e' aperto (0-1), per l'app che ci sta sotto: su iPhone
/// arretra come in Apple Music, rimpicciolita e con gli angoli tondi.
final sheetRouteProgress = ValueNotifier<double>(0);

/// Quanto il player e' stato tirato giu' col dito (0-1).
final sheetDragFraction = ValueNotifier<double>(0);

bool get _isPhone => Platform.isIOS || Platform.isAndroid;

/// L'apertura del player a tutto schermo.
///
/// Su iPhone sale con una molla, come in Apple Music, e l'app sotto
/// arretra. Sul Mac e su Windows compare in dissolvenza con un leggero
/// ingrandimento: una schermata che scorre dal basso in una finestra
/// larga e' un movimento pesante, e le app Apple per Mac non lo fanno.
///
/// E' un dialogo a tutto schermo: la pagina sotto non scivola di lato
/// come per una pagina successiva, cosa che prima faceva.
class PlayerRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;

  PlayerRoute({required this.builder}) : super(fullscreenDialog: true);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration =>
      _isPhone ? AppSprings.present.settle : const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration =>
      _isPhone ? AppSprings.dismiss.settle : const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  TickerFuture didPush() {
    animation?.addListener(_report);
    return super.didPush();
  }

  @override
  void dispose() {
    animation?.removeListener(_report);
    sheetRouteProgress.value = 0;
    super.dispose();
  }

  void _report() => sheetRouteProgress.value = animation?.value ?? 0;

  /// Da dove si apre: il punto toccato (di solito la copertina del brano
  /// in ascolto), preso all'apertura e tenuto per la chiusura.
  final Offset? _origin = lastTapPosition;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Macchia: il player si apre dentro una macchia che parte dalla
    // copertina toccata e si allarga fino a coprire lo schermo; chiudendo,
    // o tirandolo giu' sul telefono, la macchia si ritira.
    return SpotReveal(
      animation: animation,
      origin: _origin,
      seed: 'player-reveal',
      child: child,
    );
  }
}

/// L'app sotto il player, su iPhone: arretra mentre il player sale, e
/// torna avanti mentre lo si tira giu'. Fuori dal telefono non fa niente.
class SheetUnderlay extends StatelessWidget {
  final Widget child;

  const SheetUnderlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!_isPhone) return child;
    return ColoredBox(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: Listenable.merge([sheetRouteProgress, sheetDragFraction]),
        builder: (context, child) {
          final p = (sheetRouteProgress.value * (1 - sheetDragFraction.value))
              .clamp(0.0, 1.0);
          if (p == 0) return child!;
          final top = MediaQuery.paddingOf(context).top;
          return Transform.scale(
            scale: 1 - 0.07 * p,
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular((top > 20 ? 38 : 12) * p),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.25 * p),
                  BlendMode.srcATop,
                ),
                child: child,
              ),
            ),
          );
        },
        child: child,
      ),
    );
  }
}

/// Il cambio di pagina in Macchia, su tutte le piattaforme: la pagina
/// nuova compare dentro una macchia che parte dal punto toccato e si allarga
/// come inchiostro; tornando indietro si ritira verso lo stesso punto.
/// Sul telefono un trascinamento dal bordo sinistro torna indietro, come il
/// gesto di iOS.
class SpotPageTransitionsBuilder extends PageTransitionsBuilder {
  const SpotPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final origin = _origins[route] ??= lastTapPosition ?? _noOrigin;
    Widget page = SpotReveal(
      animation: animation,
      origin: identical(origin, _noOrigin) ? null : origin,
      seed: 'page-reveal',
      child: child,
    );
    if (_isPhone && !route.isFirst) page = _EdgeSwipeBack(child: page);
    return page;
  }

  /// Il punto d'origine di ogni pagina, deciso quando si apre: la chiusura
  /// deve ritirarsi verso lo stesso punto, non verso l'ultimo tocco.
  static final _origins = Expando<Offset>('spotRevealOrigin');
  static const _noOrigin = Offset(-1e9, -1e9);
}

/// L'ultimo punto toccato sullo schermo, in coordinate globali: da li'
/// parte la macchia della pagina che quel tocco apre. Lo aggiorna
/// [TapOriginTracker] in cima all'app.
Offset? lastTapPosition;

/// Registra dove si tocca, senza prendere il tocco.
class TapOriginTracker extends StatelessWidget {
  final Widget child;

  const TapOriginTracker({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) => lastTapPosition = e.position,
    child: child,
  );
}

/// Mostra [child] dentro una macchia che cresce con [animation] da
/// [origin] (globale) fino a coprire tutto. Senza origine parte dal centro
/// in basso, dove stanno i comandi.
class SpotReveal extends StatefulWidget {
  final Animation<double> animation;
  final Offset? origin;
  final String seed;
  final Widget child;

  const SpotReveal({
    super.key,
    required this.animation,
    required this.origin,
    required this.seed,
    required this.child,
  });

  @override
  State<SpotReveal> createState() => _SpotRevealState();
}

class _SpotRevealState extends State<SpotReveal> {
  /// Il ritaglio stesso: dal suo riquadro sullo schermo si ricava dove
  /// cade il punto toccato. Durante il build la pagina non ha ancora una
  /// posizione, al momento del ritaglio si'.
  final _clipKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) {
        final t = curved.value;
        if (t >= 0.999) return KeyedSubtree(key: _clipKey, child: child!);
        return ClipPath(
          key: _clipKey,
          clipper: _RevealClipper(
            t: t,
            origin: widget.origin,
            seed: widget.seed,
            clipKey: _clipKey,
          ),
          child: child,
        );
      },
    );
  }
}

class _RevealClipper extends CustomClipper<Path> {
  final double t;
  final Offset? origin;
  final String seed;
  final GlobalKey clipKey;

  _RevealClipper({
    required this.t,
    required this.origin,
    required this.seed,
    required this.clipKey,
  });

  @override
  Path getClip(Size size) {
    var o = Offset(size.width / 2, size.height * 0.85);
    final box = clipKey.currentContext?.findRenderObject();
    if (origin != null && box is RenderBox && box.attached) {
      final local = box.globalToLocal(origin!);
      if ((Offset.zero & size).inflate(40).contains(local)) o = local;
    }
    // Il raggio che basta a coprire l'angolo piu' lontano, con margine:
    // la macchia ha delle rientranze, e a fine corsa non deve lasciarne.
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - o).distance).reduce((a, b) => a > b ? a : b);
    final r = far * 1.35 * t;
    // La macchia ondeggia mentre cresce: sembra inchiostro che si allarga,
    // non un cerchio che si gonfia.
    return spotPath(
      Rect.fromCircle(center: o, radius: r),
      seed,
      wobble: 0.9,
      time: t * 3,
    );
  }

  @override
  bool shouldReclip(_RevealClipper old) => old.t != t || old.origin != origin;
}

/// Sul telefono, trascinare dal bordo sinistro verso destra torna indietro.
class _EdgeSwipeBack extends StatefulWidget {
  final Widget child;

  const _EdgeSwipeBack({required this.child});

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 22,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _dx = 0,
            onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
            onHorizontalDragEnd: (d) {
              if (_dx > 70 || (d.primaryVelocity ?? 0) > 500) {
                lastTapPosition = Offset(
                  0,
                  MediaQuery.sizeOf(context).height / 2,
                );
                Navigator.of(context).maybePop();
              }
            },
          ),
        ),
      ],
    );
  }
}
