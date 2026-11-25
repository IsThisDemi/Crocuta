import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// La macchia: la forma di Macchia, ritagliata dal manto della iena.
///
/// Ogni copertina e' una macchia irregolare invece di un quadrato
/// arrotondato, e la forma dipende dal [seed] — l'indirizzo della copertina,
/// l'id del brano — quindi lo stesso brano ha la stessa macchia dovunque
/// compaia: nella lista, nel player, nella barra. Diventa un'impronta.
///
/// E' un [OutlinedBorder] e non solo un clipper perche' serve anche come
/// forma di superfici piene — il tasto play e' una macchia del colore del
/// brano — e un bordo si mette in una [ShapeDecoration], in un [Material],
/// in un [ShapeBorderClipper] allo stesso modo.
class SpotBorder extends OutlinedBorder {
  /// Da dove nasce la forma. Due macchie con lo stesso seme sono uguali.
  final String seed;

  /// Quanto si allontana dal cerchio: 0 e' un cerchio, 1 una macchia
  /// decisa. Le macchie piccole (le righe delle liste) stanno piu' tonde:
  /// a 40px una forma molto irregolare si legge come un errore di disegno.
  final double wobble;

  /// L'istante, in secondi, per una macchia viva (vedi [spotPath]). Senza,
  /// la forma e' ferma.
  final double? time;

  const SpotBorder({
    required this.seed,
    this.wobble = 1,
    this.time,
    super.side,
  });

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      spotPath(rect, seed, wobble: wobble, time: time);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      getOuterPath(rect.deflate(side.strokeInset / 2)),
      side.toPaint(),
    );
  }

  @override
  SpotBorder copyWith({
    BorderSide? side,
    String? seed,
    double? wobble,
    double? time,
  }) => SpotBorder(
    seed: seed ?? this.seed,
    wobble: wobble ?? this.wobble,
    time: time ?? this.time,
    side: side ?? this.side,
  );

  @override
  ShapeBorder scale(double t) => copyWith(side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is SpotBorder && a.seed == seed) {
      return copyWith(
        side: BorderSide.lerp(a.side, side, t),
        wobble: lerpDouble(a.wobble, wobble, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  bool operator ==(Object other) =>
      other is SpotBorder &&
      other.seed == seed &&
      other.wobble == wobble &&
      other.time == time &&
      other.side == side;

  @override
  int get hashCode => Object.hash(seed, wobble, time, side);
}

/// FNV-1a a 32 bit: lo stesso numero per la stessa stringa su ogni
/// piattaforma e a ogni avvio, cosa che [String.hashCode] non promette.
int spotSeed(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Un generatore pseudo-casuale piccolo (mulberry32), scritto a mano
/// invece di [math.Random]: lo stesso algoritmo e' in Swift nel mini player
/// del Mac (MiniPlayerView.swift, `SpotShape`), e solo cosi' la copertina
/// ha la stessa macchia dentro e fuori dall'app. Il generatore di Dart non
/// e' documentato e non si potrebbe rifare uguale.
class SpotRandom {
  int _a;

  SpotRandom(int seed) : _a = seed & 0xffffffff;

  static int _imul(int a, int b) => (a * b) & 0xffffffff;

  /// Un numero in [0, 1).
  double nextDouble() {
    _a = (_a + 0x6D2B79F5) & 0xffffffff;
    var t = _a;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xffffffff;
    t &= 0xffffffff;
    return ((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0;
  }

  /// Un intero in [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();
}

/// Il contorno di una macchia dentro [rect].
///
/// Sei-otto punti attorno al centro, a distanze e angoli un po' sfasati,
/// uniti da una curva chiusa (Catmull-Rom tradotta in Bezier). Poi la forma
/// si stira fino a toccare i quattro lati di [rect]: una macchia che lascia
/// vuoti gli angoli a caso farebbe sembrare le copertine di misure diverse
/// anche quando non lo sono.
///
/// Con [time] la macchia e' viva: ogni punto ondeggia attorno al suo posto,
/// con un ritmo e una fase suoi (presi dallo stesso seme), come un liquido
/// che respira. A [time] zero la forma e' esattamente quella ferma: le
/// oscillazioni partono da zero, quindi una copertina che comincia a
/// muoversi non salta. Lo stesso conto e' in Swift (MiniPlayerView.swift).
Path spotPath(Rect rect, String seed, {double wobble = 1, double? time}) {
  final rnd = SpotRandom(spotSeed(seed));
  final n = 6 + rnd.nextInt(3);
  final step = 2 * math.pi / n;
  final start = rnd.nextDouble() * step;
  final w = wobble.clamp(0.0, 1.0);

  final angles = <double>[];
  final radii = <double>[];
  for (var i = 0; i < n; i++) {
    angles.add(start + i * step + (rnd.nextDouble() - 0.5) * step * 0.45 * w);
    radii.add(1 - rnd.nextDouble() * 0.24 * w);
  }
  if (time != null) {
    // Le fasi e i ritmi si tirano dopo la forma, cosi' la forma ferma resta
    // quella di sempre. Ampiezze piccole: deve respirare, non deformarsi.
    final amp = math.max(w, 0.5);
    for (var i = 0; i < n; i++) {
      final phase = rnd.nextDouble() * 2 * math.pi;
      final freq = 0.55 + rnd.nextDouble() * 0.5;
      double wave(double f, double ph) =>
          math.sin(time * f + ph) - math.sin(ph);
      radii[i] *= 1 + 0.065 * amp * wave(freq, phase);
      angles[i] += 0.09 * amp * wave(freq * 0.73, phase * 1.7);
    }
  }
  final pts = [
    for (var i = 0; i < n; i++)
      Offset(math.cos(angles[i]) * radii[i], math.sin(angles[i]) * radii[i]),
  ];

  // Catmull-Rom chiusa: ogni tratto da p1 a p2 usa i vicini p0 e p3 per le
  // tangenti, quindi la curva passa per tutti i punti senza spigoli.
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n];
    final p1 = pts[i];
    final p2 = pts[(i + 1) % n];
    final p3 = pts[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  path.close();

  final b = path.getBounds();
  if (b.width == 0 || b.height == 0) return Path()..addOval(rect);
  final m = Matrix4.identity()
    ..translateByDouble(rect.left, rect.top, 0, 1)
    ..scaleByDouble(rect.width / b.width, rect.height / b.height, 1, 1)
    ..translateByDouble(-b.left, -b.top, 0, 1);
  return path.transform(m.storage);
}

/// Ritaglia [child] a macchia.
class Spot extends StatelessWidget {
  final String seed;
  final double wobble;
  final Widget child;

  /// Un filo attorno alla macchia, per le copertine scure: sul nero il
  /// loro contorno sparisce e la forma — che e' tutto il punto — non si
  /// legge piu'.
  final Color? rim;

  /// Lo spessore del filo, di norma sottile.
  final double rimWidth;

  /// L'orologio della macchia. Di norma quello dell'app ([SpotMotion]):
  /// tutte le macchie respirano insieme. Il ritaglio si rifa' a ogni passo
  /// senza ricostruire [child].
  final ValueListenable<double>? time;

  /// Ferma anche se l'orologio dell'app gira: per il volo della copertina
  /// fra mini player e player, che dura un attimo.
  final bool still;

  const Spot({
    super.key,
    required this.seed,
    required this.child,
    this.wobble = 1,
    this.rim,
    this.rimWidth = 1.2,
    this.time,
    this.still = false,
  });

  @override
  Widget build(BuildContext context) {
    final time = still ? null : (this.time ?? SpotMotion.of(context));
    final clipped = ClipPath(
      clipper: _SpotClipper(seed, wobble, time),
      child: child,
    );
    if (rim == null) return clipped;
    return CustomPaint(
      foregroundPainter: _RimPainter(
        SpotBorder(
          seed: seed,
          wobble: wobble,
          side: BorderSide(color: rim!, width: rimWidth),
        ),
        time,
      ),
      child: clipped,
    );
  }
}

class _SpotClipper extends CustomClipper<Path> {
  final String seed;
  final double wobble;
  final ValueListenable<double>? time;

  _SpotClipper(this.seed, this.wobble, this.time) : super(reclip: time);

  @override
  Path getClip(Size size) =>
      spotPath(Offset.zero & size, seed, wobble: wobble, time: time?.value);

  @override
  bool shouldReclip(_SpotClipper old) =>
      old.seed != seed || old.wobble != wobble || old.time != time;
}

/// L'orologio di tutte le macchie dell'app: uno solo, in cima all'albero.
///
/// Ogni macchia lo legge da se' ([SpotMotion.of]) e si ridisegna quando
/// avanza, senza ricostruire cio' che contiene. Un orologio solo e non uno
/// per macchia: una Home ne mostra decine, e decine di ticker sarebbero
/// decine di callback a ogni fotogramma. Avanza a trenta fotogrammi al
/// secondo — il movimento e' lento, di piu' non si vede — e si ferma con
/// l'app nascosta o col movimento ridotto attivo nel sistema.
class SpotMotionHost extends StatefulWidget {
  final Widget child;

  const SpotMotionHost({super.key, required this.child});

  @override
  State<SpotMotionHost> createState() => _SpotMotionHostState();
}

class _SpotMotionHostState extends State<SpotMotionHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_onTick);
  double _base = 0;
  bool _visible = true;

  void _onTick(Duration elapsed) {
    final t = _base + elapsed.inMicroseconds / 1e6;
    if (t - _time.value >= 1 / 30) _time.value = t;
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = _visible && !reduce;
    if (run && !_ticker.isActive) {
      _base = _time.value;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible =
        state != AppLifecycleState.hidden && state != AppLifecycleState.paused;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SpotMotion(time: _time, child: widget.child);
}

/// Porta l'orologio delle macchie giu' per l'albero.
class SpotMotion extends InheritedWidget {
  final ValueListenable<double> time;

  const SpotMotion({super.key, required this.time, required super.child});

  /// L'orologio, o null fuori da un [SpotMotionHost] (nei test, per
  /// esempio): allora le macchie stanno ferme.
  static ValueListenable<double>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SpotMotion>()?.time;

  @override
  bool updateShouldNotify(SpotMotion old) => old.time != time;
}

/// Ricostruisce [builder] a ogni passo dell'orologio delle macchie, per le
/// macchie disegnate come superfici piene (un [SpotBorder] in una
/// decorazione). [time] e' null fuori da un [SpotMotionHost].
class SpotMotionBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, double? time) builder;

  const SpotMotionBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final clock = SpotMotion.of(context);
    if (clock == null) return builder(context, null);
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

class _RimPainter extends CustomPainter {
  final SpotBorder shape;
  final ValueListenable<double>? time;

  _RimPainter(this.shape, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) =>
      shape.copyWith(time: time?.value).paint(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_RimPainter old) => old.shape != shape || old.time != time;
}
