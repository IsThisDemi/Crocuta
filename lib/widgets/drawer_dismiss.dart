import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../design/motion.dart';

/// La schermata in riproduzione come un cassetto: tirandola giu' si chiude.
///
/// Come Apple Music: dalla maniglia in cima si trascina sempre; dal
/// contenuto solo quando e' gia' arrivato in cima, e da li' il dito che
/// continua a scendere non fa piu' scorrere la lista ma stacca il cassetto.
/// Lasciandolo, torna su — a meno che non sia sceso abbastanza, o sia stato
/// lanciato abbastanza forte, e allora si chiude.
///
/// Solo sui telefoni: col mouse non si trascina una schermata. Su desktop
/// la barretta in cima si clicca, ed Esc chiude.
class DrawerDismiss extends StatefulWidget {
  final Widget child;

  /// Di norma deciso dalla piattaforma; i test lo forzano.
  final bool? enabled;

  const DrawerDismiss({super.key, required this.child, this.enabled});

  static bool get _isPhone => Platform.isIOS || Platform.isAndroid;

  /// La fisica dello scroll dentro il cassetto.
  ///
  /// In cima si ferma invece di rimbalzare: il rimbalzo mangerebbe proprio
  /// il gesto che deve staccare il cassetto. In fondo rimbalza come prima.
  /// E mentre il cassetto e' tirato giu', la lista non si muove: il dito
  /// che risale deve prima riportare su il cassetto, poi scorrere.
  static ScrollPhysics physicsOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DrawerScope>();
    if (scope == null) return const BouncingScrollPhysics();
    return _TopClampedPhysics(pulled: scope.state._isPulled);
  }

  @override
  State<DrawerDismiss> createState() => _DrawerDismissState();
}

/// La maniglia: da qui il cassetto si trascina anche a lista non in cima.
class DrawerHandle extends StatelessWidget {
  final Widget child;

  const DrawerHandle({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_DrawerScope>();
    if (scope == null) return child;
    // Listener e non GestureDetector: non entra nell'arena dei gesti, quindi
    // i pulsanti della barra continuano a ricevere il loro tocco.
    return Listener(
      onPointerDown: (_) => scope.state._fromHandle = true,
      child: child,
    );
  }
}

class _DrawerScope extends InheritedWidget {
  final _DrawerDismissState state;

  const _DrawerScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_DrawerScope old) => false;
}

class _DrawerDismissState extends State<DrawerDismiss>
    with SingleTickerProviderStateMixin {
  /// Oltre questa discesa, lasciando si chiude.
  static const _dismissDistance = 140.0;

  /// O con un lancio verso il basso almeno cosi' veloce, anche se corto.
  static const _dismissVelocity = 700.0;

  double _offset = 0;

  /// Dove sta la lista interna. A zero, tirare giu' stacca il cassetto.
  double _pixels = 0;

  bool _fromHandle = false;
  bool _closing = false;

  /// Il trascinamento non e' ancora partito: si aspetta che il dito si sia
  /// mosso abbastanza, e in verticale, per non scambiare un tocco o un
  /// gesto di lato (la barra di avanzamento) per una chiusura.
  Offset _pending = Offset.zero;

  VelocityTracker _velocity = VelocityTracker.withKind(PointerDeviceKind.touch);

  /// Creato in initState e non pigro. Pigro, col cassetto spento — su Mac
  /// e nei test — nessuno lo toccava mai, e il primo accesso finiva in
  /// dispose: un AnimationController nato su un elemento gia' disattivato,
  /// che chiudendo il player faceva scattare un'asserzione.
  late final AnimationController _settle;

  ModalRoute<Object?>? _route;

  bool get _enabled => widget.enabled ?? DrawerDismiss._isPhone;

  bool _isPulled() => _offset > 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() => _offset = math.max(0, _settle.value));
        _reportDrag();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _settle.dispose();
    sheetDragFraction.value = 0;
    super.dispose();
  }

  /// Mostra o nasconde l'app sotto il cassetto.
  ///
  /// A riposo la route resta opaca: la shell sotto e' fuori scena, e con
  /// lei i suoi vetri di sistema — che altrimenti resterebbero composti
  /// sotto il player per tutto il tempo che e' aperto. Solo mentre lo si
  /// trascina diventa trasparente, cosi' scendendo si vede cosa c'e' sotto.
  ///
  /// E' lo stesso scambio che Flutter fa da se' durante le transizioni di
  /// una route: qui il trascinamento conta come una transizione in corso.
  void _showUnderlay(bool visible) {
    final route = _route;
    if (route == null || route.overlayEntries.isEmpty) return;
    // A meta' di una transizione vera se ne occupa gia' la route.
    if (!(route.animation?.isCompleted ?? false)) return;
    route.overlayEntries.first.opaque = visible ? false : route.opaque;
  }

  void _setOffset(double value) {
    final wasPulled = _offset > 0;
    setState(() => _offset = math.max(0, value));
    _reportDrag();
    if (!wasPulled && _offset > 0) _showUnderlay(true);
  }

  /// Quanto e' sceso, per l'app sotto che torna avanti mentre scende.
  void _reportDrag() {
    final height = MediaQuery.sizeOf(context).height;
    sheetDragFraction.value = height <= 0
        ? 0
        : (_offset / height).clamp(0.0, 1.0);
  }

  void _down(PointerDownEvent e) {
    if (_closing) return;
    _settle.stop();
    _pending = Offset.zero;
    _velocity = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) {
    if (_closing) return;
    _velocity.addPosition(e.timeStamp, e.position);
    final dy = e.delta.dy;

    if (_offset > 0) {
      _setOffset(_offset + dy);
      return;
    }

    final canPull = _fromHandle || _pixels <= 0;
    if (!canPull) {
      _pending = Offset.zero;
      return;
    }
    _pending += e.delta;
    final vertical =
        _pending.dy > kTouchSlop && _pending.dy > _pending.dx.abs();
    if (vertical) _setOffset(_pending.dy - kTouchSlop);
  }

  void _up(PointerEvent e) {
    _fromHandle = false;
    _pending = Offset.zero;
    if (_closing || _offset <= 0) return;

    final v = _velocity.getVelocity().pixelsPerSecond.dy;
    final height = MediaQuery.sizeOf(context).height;
    _settle.value = _offset;

    // Una molla che parte con la velocita' del dito, come in iOS: prima
    // erano 220 o 280 ms fissi, qualunque fosse il gesto, ed e' quello che
    // si sentiva legnoso.
    if (_offset > _dismissDistance || v > _dismissVelocity) {
      _closing = true;
      // Si porta giu' da se' e solo dopo si chiude la route: la sua
      // animazione d'uscita partirebbe dall'alto, e il player tornerebbe
      // su per un istante prima di scendere.
      _settle
          .animateWith(
            SpringSimulation(
              AppSprings.drag,
              _offset,
              height,
              math.max(v, 800),
            ),
          )
          .whenComplete(() {
            if (mounted) Navigator.of(context).maybePop();
          });
    } else {
      _settle
          .animateWith(SpringSimulation(AppSprings.drag, _offset, 0, v))
          .whenComplete(() {
            // La molla si posa a un soffio dallo zero, non sullo zero.
            if (!mounted || _closing || _offset > 1) return;
            setState(() => _offset = 0);
            _reportDrag();
            _showUnderlay(false);
          });
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _pixels = n.metrics.pixels - n.metrics.minScrollExtent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    // Gli angoli si arrotondano mentre scende, e solo allora: a riposo il
    // player e' una schermata, non una scheda. La struttura resta la stessa
    // anche a zero — cambiarla smonterebbe il contenuto, e con lui la
    // posizione della lista.
    final radius = math.min(_offset / 5, 28.0);

    return _DrawerScope(
      state: this,
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // Chiudendo col trascinamento la copertina non vola verso il
          // mini player: a quel punto sta gia' fuori schermo, in basso, e
          // la si vedrebbe risalire dal fondo. Il player e' sceso, e basta.
          child: HeroMode(
            enabled: !_closing,
            child: Transform.translate(
              offset: Offset(0, _offset),
              child: ClipRRect(
                clipBehavior: _offset > 0 ? Clip.antiAlias : Clip.none,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rimbalza in fondo ma non in cima, e resta ferma mentre il cassetto e'
/// tirato giu'.
class _TopClampedPhysics extends BouncingScrollPhysics {
  final bool Function() pulled;

  const _TopClampedPhysics({required this.pulled, super.parent});

  @override
  _TopClampedPhysics applyTo(ScrollPhysics? ancestor) =>
      _TopClampedPhysics(pulled: pulled, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      pulled() ? 0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // In cima come ClampingScrollPhysics: niente rimbalzo, cosi' il dito
    // che continua a scendere e' libero di staccare il cassetto.
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      return value - position.pixels;
    }
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) {
      return value - position.minScrollExtent;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => pulled() ? null : super.createBallisticSimulation(position, velocity);
}
