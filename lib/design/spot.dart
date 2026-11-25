import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// La musica in ascolto in un istante, per le macchie che si muovono con
/// lei (vedi services/beat_pulse.dart, che la calcola). Tutti e tre 0-1:
/// [pulse] i colpi di cassa e di basso, [snap] quelli di rullante e
/// charleston, [energy] quanto e' pieno il tratto.
typedef SpotMusic = ({double pulse, double snap, double energy});

const SpotMusic silentMusic = (pulse: 0, snap: 0, energy: 0);

/// Di quanto cresce una macchia su un colpo di basso [pulse]: fino a un
/// tredicesimo, come una cassa che spinge il cono dell'altoparlante.
double spotSwell(double pulse) => 1 + 0.075 * pulse.clamp(0.0, 2.0);

/// [rect] cresciuto attorno al suo centro per il colpo [pulse].
Rect swollenRect(Rect rect, double pulse) {
  final k = spotSwell(pulse);
  if (k == 1) return rect;
  return Rect.fromCenter(
    center: rect.center,
    width: rect.width * k,
    height: rect.height * k,
  );
}

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

  /// La musica in ascolto (vedi [SpotMotion.musicOf]): conta solo per una
  /// macchia viva.
  final SpotMusic music;

  /// Se cresce sui colpi di basso. Una superficie piena si', oltre i lati
  /// del suo riquadro; il filo attorno a una copertina no, perche' la
  /// copertina cresce gia' tutta insieme (vedi [Spot]).
  final bool swell;

  const SpotBorder({
    required this.seed,
    this.wobble = 1,
    this.time,
    this.music = silentMusic,
    this.swell = true,
    super.side,
  });

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => spotPath(
    swell ? swollenRect(rect, music.pulse) : rect,
    seed,
    wobble: wobble,
    time: time,
    music: music,
  );

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
    SpotMusic? music,
    bool? swell,
  }) => SpotBorder(
    seed: seed ?? this.seed,
    wobble: wobble ?? this.wobble,
    time: time ?? this.time,
    music: music ?? this.music,
    swell: swell ?? this.swell,
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
      other.music == music &&
      other.swell == swell &&
      other.side == side;

  @override
  int get hashCode => Object.hash(seed, wobble, time, music, swell, side);
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
///
/// Con [music] si muove con la musica in ascolto, come un visualizzatore:
/// a ogni colpo di basso alcuni lobi si gonfiano e altri cedono, a ogni
/// colpo di rullante altri ancora, ognuno quanto dice il seme; e piu' il
/// tratto e' pieno, piu' ampio e' il respiro. La forma si stira comunque
/// fino ai lati di [rect]: crescere sui colpi e' di chi la disegna
/// ([spotSwell]). In silenzio la forma e' quella senza musica.
Path spotPath(
  Rect rect,
  String seed, {
  double wobble = 1,
  double? time,
  SpotMusic music = silentMusic,
}) {
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
    // Un tratto pieno respira fino a due volte e mezzo piu' ampio.
    final breath = amp * (1 + 1.5 * music.energy.clamp(0.0, 2.0));
    for (var i = 0; i < n; i++) {
      final phase = rnd.nextDouble() * 2 * math.pi;
      final freq = 0.55 + rnd.nextDouble() * 0.5;
      double wave(double f, double ph) =>
          math.sin(time * f + ph) - math.sin(ph);
      radii[i] *= 1 + 0.065 * breath * wave(freq, phase);
      angles[i] += 0.09 * breath * wave(freq * 0.73, phase * 1.7);
    }
    // Anche i colpi dopo, per lo stesso motivo. Si tirano sempre, musica
    // o no, cosi' ogni macchia sobbalza sempre allo stesso modo: i bassi
    // spingono certi lobi, il rullante altri.
    // Fino a 2: lo slider delle Impostazioni raddoppia l'effetto.
    final bass = music.pulse.clamp(0.0, 2.0);
    final snap = music.snap.clamp(0.0, 2.0);
    for (var i = 0; i < n; i++) {
      final kick = rnd.nextDouble() * 2 - 0.7;
      final tick = rnd.nextDouble() * 2 - 1;
      if (bass == 0 && snap == 0) continue;
      radii[i] *= 1 + amp * (0.16 * bass * kick + 0.09 * snap * tick);
      angles[i] += amp * (0.05 * bass * kick + 0.06 * snap * tick);
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
    // Il battito solo con l'orologio dell'app: una macchia col suo
    // orologio (il volo, i fogli) non sa a che punto e' la musica.
    final music = still || this.time != null
        ? null
        : SpotMotion.musicListenableOf(context);
    Widget spot = ClipPath(
      clipper: _SpotClipper(seed, wobble, time, music),
      child: child,
    );
    if (rim != null) {
      spot = CustomPaint(
        foregroundPainter: _RimPainter(
          SpotBorder(
            seed: seed,
            wobble: wobble,
            swell: false,
            side: BorderSide(color: rim!, width: rimWidth),
          ),
          time,
          music,
        ),
        child: spot,
      );
    }
    if (music == null) return spot;
    // Sui colpi di basso la copertina cresce tutta, immagine compresa: il
    // ritaglio da solo non puo' uscire dalla sua immagine.
    return _Swell(music: music, child: spot);
  }
}

/// Fa crescere [child] attorno al suo centro sui colpi di basso, senza
/// ricostruirlo: cambia solo la trasformazione con cui si dipinge.
class _Swell extends SingleChildRenderObjectWidget {
  final ValueListenable<SpotMusic> music;

  const _Swell({required this.music, super.child});

  @override
  _RenderSwell createRenderObject(BuildContext context) => _RenderSwell(music);

  @override
  void updateRenderObject(BuildContext context, _RenderSwell r) =>
      r.music = music;
}

class _RenderSwell extends RenderProxyBox {
  _RenderSwell(this._music);

  ValueListenable<SpotMusic> _music;
  set music(ValueListenable<SpotMusic> v) {
    if (v == _music) return;
    if (attached) {
      _music.removeListener(markNeedsPaint);
      v.addListener(markNeedsPaint);
    }
    _music = v;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _music.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _music.removeListener(markNeedsPaint);
    super.detach();
  }

  Matrix4 get _transform {
    final k = spotSwell(_music.value.pulse);
    final c = size.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(k, k, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final k = spotSwell(_music.value.pulse);
    if (k == 1) {
      layer = null;
      context.paintChild(child!, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _transform,
        position: position,
        hitTest: (r, p) => super.hitTestChildren(r, position: p),
      );
}

class _SpotClipper extends CustomClipper<Path> {
  final String seed;
  final double wobble;
  final ValueListenable<double>? time;
  final ValueListenable<SpotMusic>? music;

  // Basta l'orologio: la musica cambia nello stesso passo.
  _SpotClipper(this.seed, this.wobble, this.time, this.music)
    : super(reclip: time);

  @override
  Path getClip(Size size) => spotPath(
    Offset.zero & size,
    seed,
    wobble: wobble,
    time: time?.value,
    music: music?.value ?? silentMusic,
  );

  @override
  bool shouldReclip(_SpotClipper old) =>
      old.seed != seed ||
      old.wobble != wobble ||
      old.time != time ||
      old.music != music;
}

/// L'orologio di tutte le macchie dell'app: uno solo, in cima all'albero.
///
/// Ogni macchia lo legge da se' ([SpotMotion.of]) e si ridisegna quando
/// avanza, senza ricostruire cio' che contiene. Un orologio solo e non uno
/// per macchia: una Home ne mostra decine, e decine di ticker sarebbero
/// decine di callback a ogni fotogramma. Avanza a trenta fotogrammi al
/// secondo — il movimento e' lento, di piu' non si vede — e si ferma con
/// l'app nascosta o col movimento ridotto attivo nel sistema.
///
/// Con [beat] le macchie si muovono con la musica, come un visualizzatore:
/// a ogni passo l'orologio chiede al brano in ascolto quanto gonfiarle
/// (il colpo di cassa o di basso di quell'istante) e quanto e' pieno il
/// tratto, che fa correre l'orologio fino a tre volte piu' svelto: un
/// ritornello fitto le fa ondeggiare di piu' di una strofa. Mentre c'e'
/// musica va a sessanta fotogrammi: un colpo dura un decimo di secondo, e
/// a trenta sarebbero tre scatti.
class SpotMotionHost extends StatefulWidget {
  final Widget child;

  /// La musica in questo istante: quanto si gonfiano le macchie e quanto
  /// e' pieno il tratto, entrambi 0-1.
  final SpotMusic Function()? beat;

  /// Quanto contano i colpi e l'energia: 0 le macchie respirano soltanto,
  /// 1 l'effetto di serie, 2 il doppio. Lo slider delle Impostazioni.
  final double intensity;

  const SpotMotionHost({
    super.key,
    required this.child,
    this.beat,
    this.intensity = 1,
  });

  @override
  State<SpotMotionHost> createState() => _SpotMotionHostState();
}

class _SpotMotionHostState extends State<SpotMotionHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _time = ValueNotifier<double>(0);
  final _music = ValueNotifier<SpotMusic>(silentMusic);
  late final Ticker _ticker = createTicker(_onTick);
  bool _visible = true;

  /// L'orologio vero, che corre piu' svelto quando la musica e' piena: si
  /// somma passo per passo, e [_time] lo pubblica solo ogni tanto.
  double _clock = 0;
  Duration _last = Duration.zero;

  /// L'ultimo istante dell'orologio in cui la musica batteva.
  double _beatSeenAt = -1e9;

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final k = widget.intensity;
    final raw = k > 0 ? widget.beat?.call() ?? silentMusic : silentMusic;
    final m = k == 1
        ? raw
        : (pulse: raw.pulse * k, snap: raw.snap * k, energy: raw.energy * k);
    // Un tratto pieno fa correre l'orologio fino a quattro volte: il
    // respiro lento di sempre diventa un ondeggiare.
    _clock += dt * (1 + 3 * m.energy);
    final t = _clock;
    final playing = m.pulse > 0.002 || m.snap > 0.002 || m.energy > 0.002;
    if (playing) _beatSeenAt = t;
    // Sessanta fotogrammi finche' la musica batte, anche fra un colpo e
    // l'altro di un brano lento: tornando a trenta nel silenzio fra due
    // battiti, l'attacco del successivo cadrebbe fra due fotogrammi.
    final beating = t - _beatSeenAt < 1.5;
    if (t - _time.value < (beating ? 1 / 60 : 1 / 30) - 1e-4) return;
    // Il battito prima dell'orologio: chi ascolta l'orologio ridisegna
    // leggendo il battito, e deve trovarlo gia' nuovo.
    _music.value = playing ? m : silentMusic;
    _time.value = t;
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final run = _visible && !reduce;
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
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
    _music.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SpotMotion(time: _time, music: _music, child: widget.child);
}

/// Porta l'orologio delle macchie giu' per l'albero.
class SpotMotion extends InheritedWidget {
  final ValueListenable<double> time;

  /// La musica in ascolto, aggiornata nello stesso passo di [time].
  final ValueListenable<SpotMusic> music;

  const SpotMotion({
    super.key,
    required this.time,
    required this.music,
    required super.child,
  });

  /// L'orologio, o null fuori da un [SpotMotionHost] (nei test, per
  /// esempio): allora le macchie stanno ferme.
  static ValueListenable<double>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SpotMotion>()?.time;

  /// La musica come valore che cambia, per chi ridisegna da se'.
  static ValueListenable<SpotMusic>? musicListenableOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SpotMotion>()?.music;

  /// La musica adesso: per le macchie costruite in un [SpotMotionBuilder],
  /// che si ricostruisce a ogni passo e la rilegge.
  static SpotMusic musicOf(BuildContext context) =>
      musicListenableOf(context)?.value ?? silentMusic;

  @override
  bool updateShouldNotify(SpotMotion old) =>
      old.time != time || old.music != music;
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
  final ValueListenable<SpotMusic>? music;

  _RimPainter(this.shape, this.time, this.music) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) => shape
      .copyWith(time: time?.value, music: music?.value ?? silentMusic)
      .paint(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.shape != shape || old.time != time || old.music != music;
}
