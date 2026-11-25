import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../providers.dart';
import 'artwork_hero.dart';
import 'crocuta_mark.dart';
import 'den_rail.dart';
import 'mini_player.dart';
import 'spot_controls.dart';
import 'thumbnail.dart';
import 'track_tile.dart' show formatDuration;

/// La navigazione del telefono: il brano in ascolto e le sezioni sono una
/// cosa sola.
///
/// Al centro la copertina del brano, a macchia, col play attaccato e
/// l'avanzamento come un anello che ne segue il bordo; attorno le quattro
/// sezioni come macchie satellite, le stesse che schizzano via dalla
/// copertina nel player. La sezione in cui sei e' il satellite grande, pieno
/// del colore del brano; le altre sono macchie scure.
///
/// - Toccando un satellite si gonfia, l'altro si sgonfia e tutto il giro
///   oscilla attorno alla copertina, come se l'urto lo avesse fatto girare.
/// - Strisciando il dito da una bolla all'altra si gonfia quella sotto il
///   dito (con un colpetto); lasciando, si apre quella.
/// - Tenendo premuta la copertina e trascinando di lato si cerca nel brano:
///   l'anello si ispessisce e sopra sale la goccia col tempo.
///
/// Il fondo non e' una fascia: e' un alone nero attorno al giro, e ai lati
/// la lista si vede passare sotto.
class WordTabBar extends ConsumerWidget {
  /// Il giro: copertina e satelliti.
  static const double orbitHeight = 88;

  /// Titolo e interpreti sopra il giro.
  static const double titleHeight = 34;

  /// Quanto sale l'alone sopra il titolo.
  static const double fade = 10;

  final List<DenDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  const WordTabBar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  /// L'altezza della barra senza l'area sicura e senza l'alone.
  static double heightFor({required bool hasTrack}) =>
      orbitHeight + (hasTrack ? titleHeight : 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(playerProvider.select((s) => s.current != null));
    final bottom = MediaQuery.paddingOf(context).bottom;

    return CustomPaint(
      painter: const _Shade(),
      child: Padding(
        padding: EdgeInsets.only(top: fade, bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasTrack) const _TitleLine(),
            SizedBox(
              height: orbitHeight,
              child: _Orbit(
                labels: [for (final d in destinations) d.label],
                selected: selected,
                onSelected: onSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'alone dietro il giro: nero pieno al centro, che si apre verso i lati e
/// verso l'alto. Un'ellisse e non una fascia, cosi' ai lati del giro la
/// pagina resta visibile; in fondo un velo leggero da bordo a bordo, perche'
/// le righe non tocchino l'indicatore di sistema.
class _Shade extends CustomPainter {
  const _Shade();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.6);
    final rx = size.width * 0.66;
    final ry = size.height * 0.78;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(rx / ry, 1);
    canvas.drawCircle(
      Offset.zero,
      ry,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0xFC000000),
            Color(0xF5000000),
            Color(0xC7000000),
            Color(0x00000000),
          ],
          stops: [0, 0.7, 0.88, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: ry)),
    );
    canvas.restore();
    final floor = Rect.fromLTRB(0, size.height - 48, size.width, size.height);
    canvas.drawRect(
      floor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x8C000000)],
        ).createShader(floor),
    );
  }

  @override
  bool shouldRepaint(_Shade old) => false;
}

class _TitleLine extends ConsumerWidget {
  const _TitleLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerProvider.select((s) => s.current));
    if (track == null) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => MiniPlayer.open(context),
      child: SizedBox(
        height: WordTabBar.titleHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                track.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  fontSize: 11.5,
                  height: 1.2,
                  color: context.colors.accentMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quanto il play sporge dalla copertina, in basso a destra.
const double _playOut = 10;

/// Lo spazio fra la copertina e il suo anello di avanzamento.
const double _ringGap = 4;

/// Dove sta ogni satellite, rispetto al centro della copertina, su un
/// telefono largo 430: due in alto, due in basso e piu' larghi, come il
/// giro della copertina nel player.
const _slots = [
  Offset(-150, 12), // Home
  Offset(-86, -14), // Search
  Offset(86, -14), // Library
  Offset(150, 12), // Queue
];

class _Orbit extends ConsumerStatefulWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  const _Orbit({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  ConsumerState<_Orbit> createState() => _OrbitState();
}

class _OrbitState extends ConsumerState<_Orbit> with TickerProviderStateMixin {
  /// Il passaggio da una bolla all'altra: la vecchia schiocca e si
  /// sgonfia, il colore vola verso la nuova come una scia di gocce ad arco
  /// sopra la copertina, la nuova si gonfia come una gelatina e le altre
  /// vengono spinte via dall'urto, e tornano.
  late final _impact = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  /// Da quale bolla a quale sta passando il colore (o e' passato).
  late int _from = widget.selected;
  late int _to = widget.selected;

  /// Il satellite sotto il dito, mentre si striscia da una bolla all'altra.
  int? _hover;

  /// Dove sono i satelliti in questo fotogramma, per sapere quale tocca il
  /// dito.
  List<Offset> _centers = const [];

  /// La frazione del brano mentre si cerca tenendo premuta la copertina, e
  /// da dove si era partiti.
  double? _scrub;
  double _scrubFrom = 0;

  static const _cover = 62.0;

  /// La lente: il puntatore (mouse sopra, o dito tenuto giu') e quanto e'
  /// accesa. Le bolle vicine al puntatore si ingrandiscono, come le icone
  /// del Dock; allontanandosi tornano piccole.
  Offset? _pointer;
  late final _lens = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  /// Quanto ingrandisce la lente un punto a [at]: 1 lontano, fino a
  /// 1 + [gain] sotto il puntatore.
  double _zoomAt(Offset at, {double gain = 0.55}) {
    final p = _pointer;
    if (p == null || _lens.value == 0) return 1;
    final d2 = (at - p).distanceSquared;
    return 1 + gain * _lens.value * math.exp(-d2 / (2 * 62 * 62));
  }

  void _point(Offset? at) {
    if (at != null) {
      _pointer = at;
      _lens.forward();
    } else {
      _lens.reverse();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(_Orbit old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _light(widget.selected);
  }

  /// Accende la bolla [to]: da quella accesa adesso parte il passaggio.
  void _light(int to) {
    if (to == _to) return;
    _from = _to;
    _to = to;
    if (MediaQuery.disableAnimationsOf(context)) {
      _impact.value = 1;
    } else {
      _impact.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _impact.dispose();
    _lens.dispose();
    super.dispose();
  }

  // --- strisciare da una bolla all'altra ---------------------------------

  void _slide(Offset at) {
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < _centers.length; i++) {
      // Distanza normalizzata sull'ellisse del satellite, con un po' di
      // margine: il dito copre piu' della punta.
      final d = at - _centers[i];
      const rx = _Satellite.big * _Satellite.aspect + 16;
      const ry = _Satellite.big + 16;
      final n = math.sqrt(
        (d.dx / rx) * (d.dx / rx) + (d.dy / ry) * (d.dy / ry),
      );
      if (n < 1 && n < bestD) {
        best = i;
        bestD = n;
      }
    }
    if (best != null && best != _hover) {
      HapticFeedback.selectionClick();
      _hover = best;
      _light(best);
    }
  }

  void _slideEnd() {
    final pick = _hover;
    _hover = null;
    if (pick != null && pick != widget.selected) {
      widget.onSelected(pick);
    } else {
      _light(widget.selected);
    }
  }

  // --- cercare nel brano tenendo premuta la copertina --------------------

  bool get _canScrub {
    final s = ref.read(playerProvider);
    return s.duration > Duration.zero && !s.mixing;
  }

  void _scrubStart() {
    if (!_canScrub) return;
    final s = ref.read(playerProvider);
    _scrubFrom = (s.position.inMilliseconds / s.duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    HapticFeedback.mediumImpact();
    setState(() => _scrub = _scrubFrom);
  }

  void _scrubMove(double dx, double width) {
    if (_scrub == null) return;
    // Tre quarti della larghezza fanno tutto il brano: abbastanza fine per
    // cercare un ritornello, abbastanza corto da non uscire dallo schermo.
    setState(() => _scrub = (_scrubFrom + dx / (width * 0.75)).clamp(0.0, 1.0));
  }

  void _scrubEnd() {
    final f = _scrub;
    if (f == null) return;
    final total = ref.read(playerProvider).duration.inMilliseconds;
    ref
        .read(playerProvider.notifier)
        .seek(Duration(milliseconds: (f * total).round()));
    setState(() => _scrub = null);
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(playerProvider.select((s) => s.current));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isLoading = ref.watch(playerProvider.select((s) => s.isLoading));
    final player = ref.read(playerProvider.notifier);
    final accent = context.colors.accent;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final scale = (w / 430).clamp(0.8, 1.15);
        final center = Offset(w / 2, box.maxHeight / 2);
        const cover = _cover;

        Widget core;
        if (track == null) {
          core = SizedBox.square(
            dimension: cover,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: AppColors.ink700,
                shape: SpotBorder(seed: 'orbit-core'),
              ),
              child: const Center(child: CrocutaMark(size: 30)),
            ),
          );
        } else {
          core = GestureDetector(
            onTap: () => MiniPlayer.open(context),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -240) MiniPlayer.open(context);
            },
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -240) {
                player.next();
              } else if (v > 240) {
                player.previous();
              }
            },
            onLongPressStart: (_) => _scrubStart(),
            onLongPressMoveUpdate: (d) => _scrubMove(d.offsetFromOrigin.dx, w),
            onLongPressEnd: (_) => _scrubEnd(),
            onLongPressCancel: () => setState(() => _scrub = null),
            // Il riquadro comprende anello e play, che sporgono: fuori dal
            // riquadro non riceverebbero i tocchi.
            child: SizedBox.square(
              dimension: cover + _ringGap * 2 + _playOut,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: cover + _ringGap * 2,
                    height: cover + _ringGap * 2,
                    child: _Ring(seed: track.thumbnailUrl, scrub: _scrub),
                  ),
                  Positioned(
                    left: _ringGap,
                    top: _ringGap,
                    width: cover,
                    height: cover,
                    child: ArtworkHero(
                      url: track.thumbnailUrl,
                      radius: AppRadius.xs,
                      child: SpotThumbnail(url: track.thumbnailUrl),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: SpotPlayButton(
                      playing: isPlaying,
                      loading: isLoading,
                      onPressed: player.toggle,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return AnimatedBuilder(
          animation: Listenable.merge([_impact, _lens]),
          builder: (context, _) {
            final t = _impact.value;
            _centers = [
              for (var i = 0; i < widget.labels.length; i++)
                center + _slots[i % _slots.length] * scale,
            ];
            final total = ref.read(playerProvider).duration;
            final moving = _from != _to && t < 1;
            final a = _centers[_from];
            final b = _centers[_to];

            // La scia: cinque gocce che partono una dopo l'altra dalla bolla
            // vecchia e volano ad arco sopra la copertina fino alla nuova,
            // gonfiandosi a meta' strada e rimpicciolendo all'arrivo.
            final arcTop = math.min(math.min(a.dy, b.dy), center.dy) - 40;
            final control = Offset((a.dx + b.dx) / 2, arcTop);
            final trail = <(Offset, double)>[
              if (moving)
                for (var k = 0; k < 5; k++)
                  if (((t - k * 0.045) / 0.4) case final tk
                      when tk > 0 && tk < 1)
                    (
                      _bezier(
                        a,
                        control,
                        b,
                        Curves.easeInOutCubic.transform(tk),
                      ),
                      (11.5 - k * 1.6) * math.sqrt(math.sin(math.pi * tk)),
                    ),
            ];

            // La copertina sussulta quando la scia le passa sopra.
            final over = ((t - 0.08) / 0.34).clamp(0.0, 1.0);
            final coverKick = moving ? 0.06 * math.sin(math.pi * over) : 0.0;

            return MouseRegion(
              onHover: (e) => _point(e.localPosition),
              onExit: (_) => _point(null),
              child: Listener(
                // Col dito la lente si accende tenendolo giu', e lo segue.
                onPointerDown: (e) {
                  if (e.kind != PointerDeviceKind.mouse)
                    _point(e.localPosition);
                },
                onPointerMove: (e) {
                  if (e.kind != PointerDeviceKind.mouse)
                    _point(e.localPosition);
                },
                onPointerUp: (e) {
                  if (e.kind != PointerDeviceKind.mouse) _point(null);
                },
                onPointerCancel: (e) {
                  if (e.kind != PointerDeviceKind.mouse) _point(null);
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (d) => _slide(d.localPosition),
                  onPanUpdate: (d) => _slide(d.localPosition),
                  onPanEnd: (_) => _slideEnd(),
                  onPanCancel: () {
                    _hover = null;
                    _light(widget.selected);
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < widget.labels.length; i++)
                        _placed(i, _centers[i], t, moving),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: SpotMotionBuilder(
                            builder: (context, clock) => CustomPaint(
                              painter: _TrailPainter(trail, accent, clock),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: center.dx - cover / 2 - _ringGap,
                        top: center.dy - cover / 2 - _ringGap,
                        child: Transform.scale(
                          scale: (1 + coverKick) * _zoomAt(center, gain: 0.35),
                          // Dal centro della copertina, non del riquadro col
                          // play che sporge.
                          origin: Offset(-(_playOut) / 2, -(_playOut) / 2),
                          child: core,
                        ),
                      ),
                      // La goccia col tempo, sopra la copertina, mentre si cerca.
                      Positioned(
                        left: center.dx - 33,
                        top: center.dy - cover / 2 - _ringGap - 46,
                        width: 66,
                        height: 38,
                        child: IgnorePointer(
                          child: AnimatedScale(
                            scale: _scrub != null ? 1 : 0,
                            alignment: Alignment.bottomCenter,
                            duration: const Duration(milliseconds: 260),
                            curve: _scrub != null
                                ? Curves.easeOutBack
                                : Curves.easeIn,
                            child: TimeDrop(
                              text: formatDuration(total * (_scrub ?? 0)),
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Offset _bezier(Offset p0, Offset p1, Offset p2, double t) =>
      p0 * ((1 - t) * (1 - t)) + p1 * (2 * (1 - t) * t) + p2 * (t * t);

  Widget _placed(int i, Offset at, double t, bool moving) {
    // Quanto e' accesa, e come si deforma, in questo fotogramma.
    var on = i == _to ? 1.0 : 0.0;
    var sx = 1.0, sy = 1.0;
    var push = Offset.zero;
    if (moving) {
      if (i == _from) {
        // Schiocca: si allarga un attimo e si sgonfia, mentre il colore
        // se ne va.
        final u = (t / 0.32).clamp(0.0, 1.0);
        on = 1 - Curves.easeInCubic.transform(u);
        final pop = math.sin(math.pi * u);
        sx = 1 + 0.16 * pop;
        sy = 1 - 0.12 * pop;
      } else if (i == _to) {
        // La gelatina: il colore arriva, si gonfia e oscilla, schiacciata
        // e allungata, finche' si assesta.
        final u = ((t - 0.34) / 0.66).clamp(0.0, 1.0);
        on = Curves.easeOutCubic.transform((u * 2.4).clamp(0.0, 1.0));
        final jelly = 0.2 * math.sin(u * math.pi * 3.4) * math.pow(1 - u, 1.6);
        sx = 1 + jelly;
        sy = 1 - jelly * 0.9;
      }
      if (i != _to) {
        // L'urto all'arrivo spinge via le altre, prima le vicine.
        final away = _centers[i] - _centers[_to];
        final d = away.distance;
        final delay = 0.36 + d / 2400;
        final u = ((t - delay) / 0.6).clamp(0.0, 1.0);
        if (d > 0) {
          push = away / d * (10 * math.sin(u * math.pi * 2) * (1 - u));
        }
      }
    }

    // Il riquadro e' quello del satellite grande: cosi' crescendo non si
    // sposta, e le gocce hanno spazio attorno.
    const box = Size(
      _Satellite.big * _Satellite.aspect * 2 + 8,
      _Satellite.big * 2,
    );
    final zoom = _zoomAt(at);
    return Positioned(
      left: at.dx + push.dx - box.width / 2,
      top: at.dy + push.dy - box.height / 2,
      width: box.width,
      height: box.height,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(sx * zoom, sy * zoom, 1),
        child: _Satellite(
          label: widget.labels[i],
          on: on,
          selected: i == widget.selected,
          // Le gocce schizzano verso l'esterno per i satelliti in alto; per
          // quelli in basso, che stanno gia' sul bordo dello schermo, verso
          // l'interno.
          outward: () {
            final slot = _slots[i % _slots.length];
            final side = slot.dx < 0 ? -1.0 : 1.0;
            return slot.dy < 0 ? side : -side;
          }(),
          onTap: () => widget.onSelected(i),
        ),
      ),
    );
  }
}

/// La scia di gocce fra una bolla e l'altra.
class _TrailPainter extends CustomPainter {
  final List<(Offset, double)> drops;
  final Color color;
  final double? time;

  _TrailPainter(this.drops, this.color, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    var k = 0;
    for (final (at, r) in drops) {
      if (r <= 0.3) continue;
      canvas.drawPath(
        spotPath(
          Rect.fromCircle(center: at, radius: r),
          'trail-${k++}',
          wobble: 0.7,
          time: time == null ? null : time! * 3,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => true;
}

/// L'avanzamento del brano: un anello che segue il bordo della copertina,
/// della stessa forma e mosso dallo stesso orologio, appena piu' largo.
/// Mentre si cerca si ispessisce.
class _Ring extends ConsumerWidget {
  final String seed;
  final double? scrub;

  const _Ring({required this.seed, required this.scrub});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final total = duration.inMilliseconds;
    final live = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    final accent = context.colors.accent;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: scrub != null ? 5 : 2.5),
      duration: const Duration(milliseconds: 200),
      builder: (context, width, _) => SpotMotionBuilder(
        builder: (context, t) => CustomPaint(
          painter: _RingPainter(
            seed: seed,
            fraction: scrub ?? live,
            time: t,
            width: width,
            color: accent,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final String seed;
  final double fraction;
  final double? time;
  final double width;
  final Color color;

  _RingPainter({
    required this.seed,
    required this.fraction,
    required this.time,
    required this.width,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = spotPath(
      (Offset.zero & size).deflate(width / 2),
      seed,
      time: time,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke..color = Colors.white.withValues(alpha: 0.1));
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null || fraction <= 0) return;
    canvas.drawPath(
      metric.extractPath(0, metric.length * fraction),
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.time != time ||
      old.width != width ||
      old.color != color ||
      old.seed != seed;
}

class _Satellite extends StatelessWidget {
  /// Il raggio verticale del satellite acceso e di quelli spenti.
  static const double big = 27;
  static const double small = 20;

  /// Quanto sono piu' larghe che alte: ci devono stare le parole.
  static const double aspect = 1.45;

  final String label;

  /// Quanto e' acceso, da 0 a 1: misura, colore, testo e gocce.
  final double on;
  final bool selected;
  final double outward;
  final VoidCallback onTap;

  const _Satellite({
    required this.label,
    required this.on,
    required this.selected,
    required this.outward,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = colors.accent;
    // Spente non sono grigie: un nero appena tinto del brano.
    final dark = Color.lerp(AppColors.ink700, accent, 0.14)!;
    final v = on.clamp(0.0, 1.0);
    final ry = lerpDouble(small, big, v)!;
    final rx = ry * aspect;

    return SpotMotionBuilder(
      builder: (context, t) {
        // Ogni satellite galleggia per conto suo attorno al suo posto.
        final rnd = SpotRandom(spotSeed('orbit-$label'));
        final phase = rnd.nextDouble() * 2 * math.pi;
        final speed = 0.4 + rnd.nextDouble() * 0.3;
        final float = t == null
            ? Offset.zero
            : Offset(
                3 * (math.sin(t * speed + phase) - math.sin(phase)),
                3 * (math.cos(t * speed * 0.8 + phase) - math.cos(phase)),
              );
        return Transform.translate(
          offset: float,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Le gocce attorno al satellite acceso.
              for (final (dx, dy, r, seed) in [
                (0.95, -0.95, 5.0, 'a'),
                (1.22, -0.25, 3.5, 'b'),
              ])
                Transform.translate(
                  offset: Offset(outward * dx * rx, dy * ry),
                  child: Transform.scale(
                    scale: v,
                    child: SizedBox.square(
                      dimension: r * 2,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: accent,
                          shape: SpotBorder(
                            seed: 'orbit-drop-$label-$seed',
                            time: t == null ? null : t * 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                selected: selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: SizedBox(
                    width: rx * 2,
                    height: ry * 2,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: Color.lerp(dark, accent, v),
                        shape: SpotBorder(
                          seed: 'orbit-$label',
                          wobble: 0.85,
                          time: t == null ? null : t * 1.4,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          style: context.texts.titleLarge!.copyWith(
                            fontSize: lerpDouble(12, 14.5, v),
                            fontWeight: v > 0.5
                                ? FontWeight.w800
                                : FontWeight.w700,
                            height: 1,
                            color: Color.lerp(
                              colors.accentMuted,
                              AppColors.ink900,
                              v,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
