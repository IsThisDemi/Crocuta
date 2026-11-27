import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';

/// Le due forme della barra.
enum SpotSliderStyle {
  /// L'avanzamento di un brano: l'onda del brano, barrette morbide alte
  /// quanto il suono in quel punto ([SpotSlider.wave]), accese fin dove
  /// si e' arrivati. Attorno al punto in ascolto saltano sui colpi.
  wave,

  /// Il volume e gli altri livelli: un filo denso coi bordi che ondeggiano,
  /// la testa una goccia che si fonde con lui, e davanti la fila di
  /// macchioline del manto che il filo si mangia.
  goo,
}

/// La barra di Crocuta, al posto dello Slider di Material, che era una
/// riga e un pallino come in ogni altra app. Due forme ([SpotSliderStyle]):
/// l'onda per l'avanzamento del brano, la goccia densa per il volume.
///
/// Col mouse sopra tutto si ingrossa. Presa, sale una goccia col valore
/// scritto dentro ([label]) — il tempo, la percentuale —, tenuta alla
/// barra da una gocciolina, come la barra del mini player.
///
/// Si trascina, si tocca per saltare a un punto, e da tastiera le frecce
/// la spostano. [onChanged] null la spegne.
class SpotSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;

  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  /// Gli scatti: le macchioline diventano i gradini, una per scatto.
  final int? divisions;

  /// Il testo della goccia mentre la si tiene; senza, la goccia non sale.
  final String Function(double value)? label;

  /// Il valore letto dal VoiceOver; di norma la percentuale.
  final String Function(double value)? semanticValue;
  final String? semanticLabel;

  /// La testa si vede anche a riposo (l'avanzamento) o solo toccandola
  /// (il volume, che a riposo e' una linea e non ruba la scena).
  final bool headAtRest;

  /// Il colore del filo, di norma quello del brano.
  final Color? color;

  /// Il colore del filo a riposo, se diverso: il volume sta spento finche'
  /// non lo si tocca, per non fare a gara con l'avanzamento.
  final Color? idleColor;

  /// La forma della testa e delle macchioline.
  final String seed;

  /// L'altezza che si prende col dito: il filo e' sottile, la presa no.
  final double height;

  final SpotSliderStyle style;

  /// Per [SpotSliderStyle.wave]: quanto suona il brano lungo la barra,
  /// valori 0-1 dall'inizio alla fine, quanti si vuole. Null finche' il
  /// brano non e' analizzato: allora l'onda e' bassa e piatta, e quando
  /// arriva ci si trasforma.
  final List<double>? wave;

  /// Per [SpotSliderStyle.wave]: il mix AutoMix che verra'. Nel suo
  /// tratto l'onda mostra gia' i due brani intrecciati come andranno, e
  /// dopo non c'e' piu' niente: il brano finisce li'.
  final SliderMixPreview? mix;

  const SpotSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.divisions,
    this.label,
    this.semanticValue,
    this.semanticLabel,
    this.headAtRest = true,
    this.color,
    this.idleColor,
    this.seed = 'spot-slider',
    this.height = 40,
    this.style = SpotSliderStyle.goo,
    this.wave,
    this.mix,
  });

  @override
  State<SpotSlider> createState() => _SpotSliderState();
}

class _SpotSliderState extends State<SpotSlider> with TickerProviderStateMixin {
  /// Mouse sopra, o fuoco da tastiera: il filo si ingrossa.
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
  );

  /// Presa: la testa cresce e la goccia sale.
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _liftCurve = CurvedAnimation(
    parent: _lift,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  /// L'onda che arriva: dalla vecchia (o dalla piatta) alla nuova.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );
  late final Animation<double> _morphCurve = CurvedAnimation(
    parent: _morph,
    curve: Curves.easeOutCubic,
  );
  List<double>? _waveFrom;

  /// Dove sta il dito, finche' la si tiene: la barra lo segue subito,
  /// anche prima che chi la usa abbia ridisegnato il valore.
  double? _held;
  bool _hover = false;
  bool _focused = false;

  bool get _enabled => widget.onChanged != null && widget.max > widget.min;

  double get _span => widget.max - widget.min;

  double _fractionOf(double value) =>
      _span <= 0 ? 0 : ((value - widget.min) / _span).clamp(0.0, 1.0);

  double _valueOf(double fraction) => widget.min + fraction * _span;

  double _snap(double f) {
    final d = widget.divisions;
    if (d == null || d <= 0) return f.clamp(0.0, 1.0);
    return ((f * d).round() / d).clamp(0.0, 1.0);
  }

  void _syncGrow() {
    final on = _enabled && (_hover || _focused || _held != null);
    on ? _grow.forward() : _grow.reverse();
  }

  // --- Il dito -----------------------------------------------------------

  void _start(double dx, double width) {
    if (!_enabled) return;
    final f = _snap(dx / width);
    HapticFeedback.selectionClick();
    setState(() => _held = f);
    _lift.forward();
    _syncGrow();
    widget.onChangeStart?.call(_valueOf(f));
    widget.onChanged?.call(_valueOf(f));
  }

  void _move(double dx, double width) {
    if (!_enabled || _held == null) return;
    final f = _snap(dx / width);
    if (f == _held) return;
    if (widget.divisions != null) HapticFeedback.selectionClick();
    setState(() => _held = f);
    widget.onChanged?.call(_valueOf(f));
  }

  void _end() {
    final f = _held;
    if (f == null) return;
    setState(() => _held = null);
    _lift.reverse();
    _syncGrow();
    if (_enabled) widget.onChangeEnd?.call(_valueOf(f));
  }

  /// Un tocco senza trascinare: salta li'.
  void _tap(double dx, double width) {
    _start(dx, width);
    _end();
  }

  // --- La tastiera e il VoiceOver ---------------------------------------

  double get _step {
    final d = widget.divisions;
    return d != null && d > 0 ? 1 / d : 0.05;
  }

  void _nudge(int direction) {
    if (!_enabled) return;
    final from = _fractionOf(widget.value);
    final f = _snap(from + direction * _step);
    final v = _valueOf(f);
    widget.onChangeStart?.call(v);
    widget.onChanged?.call(v);
    widget.onChangeEnd?.call(v);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!_enabled || e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowUp) {
      _nudge(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowDown) {
      _nudge(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _semantic(double f) =>
      widget.semanticValue?.call(_valueOf(f)) ?? '${(f * 100).round()}%';

  @override
  void didUpdateWidget(SpotSlider old) {
    super.didUpdateWidget(old);
    if (!identical(old.wave, widget.wave) &&
        !listEquals(old.wave, widget.wave)) {
      _waveFrom = old.wave;
      _morph.forward(from: 0);
    }
    if (!_enabled && _held != null) {
      _held = null;
      _lift.reverse();
    }
    _syncGrow();
  }

  @override
  void dispose() {
    _grow.dispose();
    _lift.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.colors.accent;
    final fraction = _held ?? _snap(_fractionOf(widget.value));
    final label = widget.label;
    final style = context.texts.titleSmall?.copyWith(
      color: AppColors.ink900,
      fontWeight: FontWeight.w800,
      fontFeatures: AppTypography.tabular,
    );

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      enabled: _enabled,
      value: _semantic(fraction),
      increasedValue: _semantic(_snap(fraction + _step)),
      decreasedValue: _semantic(_snap(fraction - _step)),
      onIncrease: _enabled ? () => _nudge(1) : null,
      onDecrease: _enabled ? () => _nudge(-1) : null,
      child: Focus(
        canRequestFocus: _enabled,
        onKeyEvent: _onKey,
        onFocusChange: (f) {
          _focused = f;
          _syncGrow();
        },
        child: MouseRegion(
          cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) {
            _hover = true;
            _syncGrow();
          },
          onExit: (_) {
            _hover = false;
            _syncGrow();
          },
          child: LayoutBuilder(
            builder: (context, box) {
              final width = math.max(box.maxWidth, 1.0);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: _enabled
                    ? (d) => _tap(d.localPosition.dx, width)
                    : null,
                onHorizontalDragStart: _enabled
                    ? (d) => _start(d.localPosition.dx, width)
                    : null,
                onHorizontalDragUpdate: _enabled
                    ? (d) => _move(d.localPosition.dx, width)
                    : null,
                onHorizontalDragEnd: _enabled ? (_) => _end() : null,
                onHorizontalDragCancel: _end,
                child: SizedBox(
                  width: double.infinity,
                  height: widget.height,
                  child: CustomPaint(
                    painter: _SpotSliderPainter(
                      fraction: fraction,
                      enabled: _enabled,
                      grow: _grow,
                      lift: _liftCurve,
                      time: SpotMotion.of(context),
                      music: SpotMotion.musicListenableOf(context),
                      color: color,
                      idleColor: widget.idleColor ?? color,
                      seed: widget.seed,
                      headAtRest: widget.headAtRest,
                      divisions: widget.divisions,
                      style: widget.style,
                      wave: widget.wave,
                      waveFrom: _waveFrom,
                      mix: widget.mix,
                      morph: _morphCurve,
                      label: label == null
                          ? null
                          : TextPainter(
                              text: TextSpan(
                                text: label(_valueOf(fraction)),
                                style: style,
                              ),
                              textDirection: Directionality.of(context),
                              maxLines: 1,
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpotSliderPainter extends CustomPainter {
  final double fraction;
  final bool enabled;
  final Animation<double> grow;
  final Animation<double> lift;
  final Animation<double> morph;
  final ValueListenable<double>? time;
  final ValueListenable<SpotMusic>? music;
  final Color color;
  final Color idleColor;
  final String seed;
  final bool headAtRest;
  final int? divisions;
  final SpotSliderStyle style;
  final List<double>? wave;
  final List<double>? waveFrom;
  final SliderMixPreview? mix;
  final TextPainter? label;

  _SpotSliderPainter({
    required this.fraction,
    required this.enabled,
    required this.grow,
    required this.lift,
    required this.morph,
    required this.time,
    required this.music,
    required this.color,
    required this.idleColor,
    required this.seed,
    required this.headAtRest,
    required this.divisions,
    required this.style,
    required this.wave,
    required this.waveFrom,
    required this.mix,
    required this.label,
  }) : super(repaint: Listenable.merge([grow, lift, morph, time, music]));

  /// Un numero a caso ma sempre lo stesso per l'elemento [i]: la barra ha
  /// la stessa forma a ogni fotogramma, e la stessa ovunque.
  static double _rand(int i, int k) {
    final v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = grow.value.clamp(0.0, 1.0);
    final l = lift.value;
    final t = time?.value ?? 0;
    final m = enabled ? (music?.value ?? silentMusic) : silentMusic;
    final top = switch (style) {
      SpotSliderStyle.wave => _paintWave(canvas, size, g, l, t, m),
      SpotSliderStyle.goo => _paintGoo(canvas, size, g, l, t, m),
    };
    if (label != null && l > 0.01) {
      _paintDrop(
        canvas,
        size.width,
        Offset(fraction * size.width, top),
        l,
        t,
        m,
      );
    }
  }

  // --- L'onda --------------------------------------------------------------

  /// Il livello dell'onda a [u] della barra. Un punto e non una media:
  /// l'onda ha i colpi di ogni istante (vedi waveformOf), e la media li
  /// spianerebbe.
  static double _levelAt(List<double>? w, double u) {
    if (w == null || w.isEmpty) return _flat;
    return w[(u * w.length).floor().clamp(0, w.length - 1)];
  }

  /// Una barretta nel tratto del mix che verra': due barrette sottili
  /// affiancate, chi esce nel suo colore e chi entra nel suo, alte quanto
  /// suoneranno — l'onda di ognuno per il volume che gli dara' AutoMix.
  /// Dopo il mix, un puntino: li' il brano non si sentira'.
  void _paintMixBar(
    Canvas canvas,
    SliderMixPreview mx,
    double u,
    double cx,
    double cy,
    double outLevel,
    double bar,
    double maxH,
    double minH,
    bool played,
  ) {
    if (u > mx.to) {
      canvas.drawCircle(
        Offset(cx, cy),
        1.1,
        Paint()..color = Colors.white.withValues(alpha: 0.12),
      );
      return;
    }
    final k = mx.to <= mx.from ? 1.0 : (u - mx.from) / (mx.to - mx.from);
    final inLevel = mx.inLevelAt(k);
    final thin = bar * 0.62;
    final gap = bar * 0.36;
    for (final (dx, level, gain, c, alpha) in [
      (-gap, outLevel, mx.outGainAt(k), color, played ? 1.0 : 0.5),
      (gap, inLevel, mx.inGainAt(k), mx.color, played ? 1.0 : 0.85),
    ]) {
      final h = minH + (maxH - minH) * level * (0.12 + 0.88 * gain);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + dx, cy), width: thin, height: h),
          Radius.circular(thin / 2),
        ),
        Paint()..color = c.withValues(alpha: alpha),
      );
    }
  }

  /// L'onda di un brano non ancora analizzato: bassa e piatta.
  static const double _flat = 0.22;

  /// Ritorna la cima della barretta sotto la testa, da dove sale la goccia.
  double _paintWave(
    Canvas canvas,
    Size size,
    double g,
    double l,
    double t,
    SpotMusic m,
  ) {
    final w = size.width;
    final cy = size.height / 2;
    final x = fraction * w;
    final lc = l.clamp(0.0, 1.0);
    final bass = m.pulse.clamp(0.0, 2.0);
    final energy = m.energy.clamp(0.0, 2.0);
    final k = morph.value;

    const pitch = 6.0;
    final count = math.max(8, (w / pitch).floor());
    final step = w / count;
    final bar = math.min(3.4, step * 0.58) * (1 + 0.12 * g);
    final maxH = math.min(24.0, size.height - 10) * (1 + 0.14 * g);
    const minH = 3.0;

    final played = Paint()..color = color;
    final ahead = Paint()
      ..color = Colors.white.withValues(
        alpha: enabled ? lerpDouble(0.18, 0.26, g)! : 0.1,
      );
    var headTop = cy - maxH / 2;

    final mx = enabled ? mix : null;
    for (var i = 0; i < count; i++) {
      final u = (i + 0.5) / count;
      final from = _levelAt(waveFrom, u);
      final to = _levelAt(wave, u);
      final v = enabled ? lerpDouble(from, to, k)! : _flat;
      final cx = (i + 0.5) * step;
      if (mx != null && u > mx.from) {
        _paintMixBar(canvas, mx, u, cx, cy, v, bar, maxH, minH, cx <= x);
        continue;
      }
      // I colpi fanno saltare le barrette attorno al punto in ascolto, e
      // quelle vicine piu' di quelle lontane: un'onda che parte da li'.
      final near = math.exp(-(cx - x).abs() / 70);
      final jump = 1 + 0.45 * bass * near * (0.6 + 0.4 * _rand(i, 7));
      final sway = 1 + 0.07 * energy * math.sin(t * 2.2 + i * 0.55);
      final h = (minH + (maxH - minH) * v) * jump * sway;
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: bar, height: h),
        Radius.circular(bar / 2),
      );
      final left = cx - bar / 2, right = cx + bar / 2;
      final rest = ahead;
      if (right <= x) {
        canvas.drawRRect(r, played);
      } else if (left >= x) {
        canvas.drawRRect(r, rest);
      } else {
        // La barretta dove si e' arrivati: accesa fin li'.
        canvas.drawRRect(r, rest);
        canvas
          ..save()
          ..clipRect(Rect.fromLTRB(left, 0, x, size.height));
        canvas.drawRRect(r, played);
        canvas.restore();
      }
      if (left <= x && x < right + step - bar) headTop = cy - h / 2;
    }

    // La testa: un taglio bianco dove si e' arrivati, solo toccandola. A
    // riposo l'onda accesa dice gia' tutto.
    final show = enabled ? math.max(g, lc) : 0.0;
    if (show > 0.01) {
      final hh = (maxH + 10) * (0.4 + 0.6 * show);
      final cut = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: 3, height: hh),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(
        cut,
        Paint()..color = Colors.white.withValues(alpha: show),
      );
      headTop = cy - hh / 2;
    }
    return headTop;
  }

  // --- La goccia densa -----------------------------------------------------

  /// Ritorna la cima della testa, da dove sale la goccia.
  double _paintGoo(
    Canvas canvas,
    Size size,
    double g,
    double l,
    double t,
    SpotMusic m,
  ) {
    final w = size.width;
    final cy = size.height / 2;
    final x = fraction * w;
    final lc = l.clamp(0.0, 1.0);
    final bass = m.pulse.clamp(0.0, 2.0);
    final snap = m.snap.clamp(0.0, 2.0);
    final energy = m.energy.clamp(0.0, 2.0);
    final ink = Color.lerp(idleColor, color, math.max(g, lc))!;

    // Lo spessore del filo: sottile a riposo, piu' pieno sotto il mouse, e
    // sui colpi di basso si gonfia.
    final thick = (4.6 + 3.4 * g + 0.8 * lc) * (1 + 0.25 * bass);
    final restHead = headAtRest && enabled ? 6.5 : 0.0;
    final r = enabled
        ? lerpDouble(lerpDouble(restHead, 9.5, g)!, 11.5, lc)! *
              spotSwell(bass) *
              (1 + 0.04 * math.sin(t * 2.6))
        : 0.0;

    _paintDots(canvas, w, cy, x, thick, r, g, t, snap);

    // Il contorno: il filo coi bordi che ondeggiano, che vicino alla testa
    // si allarga in un collo e ci si fonde, come un liquido denso.
    final amp = 0.16 + 0.18 * energy;
    double edge(double at, double phase) =>
        1 +
        amp * math.sin(at * 0.055 - t * 1.8 + phase) +
        0.5 * amp * math.sin(at * 0.13 + t * 1.1 + phase * 2);
    final cap = thick * 0.9;
    final end = r > 0.5 ? x + r : x;
    if (end < 1) return cy - r;
    double half(double at, double phase) {
      var h = 0.0;
      if (at <= x) {
        final a = (at / cap).clamp(0.0, 1.0);
        final b = r > 0.5 ? 1.0 : ((x - at) / cap).clamp(0.0, 1.0);
        final m0 = math.min(a, b);
        h = thick / 2 * math.sqrt(m0 * (2 - m0)) * edge(at, phase);
      }
      if (r > 0.5) {
        final d = at - x;
        final circle = math.sqrt(math.max(0, r * r - d * d));
        // Il collo: dove il filo sale verso la testa.
        final neckFrom = x - 2.6 * r;
        final u = ((at - neckFrom) / (2.6 * r)).clamp(0.0, 1.0);
        final s = u * u * (3 - 2 * u);
        final neck = at <= x ? lerpDouble(h, r * 0.92, s * s)! : 0.0;
        h = math.max(h, math.max(circle, neck));
      }
      return h;
    }

    final steps = math.max(2, (end / 2.5).ceil());
    final upper = <Offset>[], lower = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final at = end * i / steps;
      upper.add(Offset(at, cy - half(at, 0)));
      lower.add(Offset(at, cy + half(at, 2.1)));
    }
    final path = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (final p in upper.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in lower.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    if (bass > 0.02) {
      canvas.drawPath(
        path,
        Paint()
          ..color = ink.withValues(alpha: (0.3 * bass).clamp(0.0, 0.5))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 4 * bass),
      );
    }
    if (r > 0.5 && g > 0.01) {
      canvas.drawShadow(
        Path()..addOval(Rect.fromCircle(center: Offset(x, cy), radius: r)),
        Colors.black.withValues(alpha: 0.45 * g),
        3,
        false,
      );
    }
    canvas.drawPath(path, Paint()..color = ink);
    return cy - math.max(r, thick / 2);
  }

  /// Il tratto che manca: macchioline irregolari, il manto della iena.
  void _paintDots(
    Canvas canvas,
    double w,
    double cy,
    double x,
    double thick,
    double head,
    double g,
    double t,
    double snap,
  ) {
    final d = divisions;
    // Con gli scatti, una macchiolina per scatto; se no fitte quanto basta
    // a leggerle come una fila, non come una linea tratteggiata.
    final count = d != null && d > 0
        ? d
        : math.max(1, (w / math.max(8.0, thick * 1.9)).round());
    final spacing = w / count;
    final paint = Paint()
      ..color = Colors.white.withValues(
        alpha: enabled ? lerpDouble(0.2, 0.3, g)! : 0.1,
      );
    // Il filo se le mangia: oltre la testa, e un po' prima che arrivi.
    final eaten = x + math.max(head, thick / 2) + 2;
    for (var i = 0; i <= count; i++) {
      final cx = i * spacing;
      if (cx < eaten) continue;
      final big = 0.6 + 0.45 * _rand(i, 1);
      final breathe = 1 + 0.1 * math.sin(t * 1.3 + i * 1.7);
      final twitch = 1 + 0.35 * snap * (_rand(i, 4) - 0.3);
      final r = thick * 0.42 * big * breathe * twitch * (d != null ? 1.2 : 1);
      // Appena dopo la testa crescono, come se ne uscissero.
      final near = ((cx - eaten) / (spacing * 1.5)).clamp(0.0, 1.0);
      final rr = r * (0.35 + 0.65 * near);
      final aspect = 0.68 + 0.32 * _rand(i, 2);
      final dy = (_rand(i, 5) - 0.5) * thick * 0.35;
      canvas
        ..save()
        ..translate(cx, cy + dy)
        ..rotate(_rand(i, 3) * math.pi);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: rr * 2,
          height: rr * 2 * aspect,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  // --- La goccia col valore ------------------------------------------------

  /// Sale da [from] (la cima della testa) mentre la si tiene.
  void _paintDrop(
    Canvas canvas,
    double w,
    Offset from,
    double l,
    double t,
    SpotMusic m,
  ) {
    final tp = label!..layout();
    final dw = tp.width + 22;
    final dh = tp.height + 12;
    final lc = l.clamp(0.0, 1.0);
    // Dentro la barra ai due capi, come quella del mini player: in fondo
    // al brano non deve uscire dallo schermo.
    final cx = w <= dw ? w / 2 : from.dx.clamp(dw / 2, w - dw / 2);
    final target = Offset(cx, from.dy - 10 - dh / 2);
    final center = Offset.lerp(from, target, lc)!;
    final rect = Rect.fromCenter(center: center, width: dw * l, height: dh * l);
    if (rect.width < 1 || rect.height < 1) return;

    // La gocciolina fra la barra e la goccia.
    final neckAt = Offset(
      lerpDouble(from.dx, cx, 0.35)!,
      lerpDouble(from.dy, rect.bottom, 0.5)!,
    );
    final neck = 7 * lc;
    if (neck > 0.5) {
      canvas.drawPath(
        spotPath(
          Rect.fromCenter(center: neckAt, width: neck, height: neck),
          '$seed-neck',
          time: t * 2,
          music: m,
        ),
        Paint()..color = color,
      );
    }

    final path = spotPath(
      rect,
      '$seed-drop',
      wobble: 0.7,
      time: t * 2.2,
      music: m,
    );
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.55), 6, false);
    canvas.drawPath(path, Paint()..color = color);

    final a = ((l - 0.45) / 0.55).clamp(0.0, 1.0);
    if (a <= 0) return;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(l.clamp(0.0, 1.2));
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: a));
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas
      ..restore()
      ..restore();
  }

  @override
  bool shouldRepaint(_SpotSliderPainter old) =>
      old.fraction != fraction ||
      old.enabled != enabled ||
      old.color != color ||
      old.idleColor != idleColor ||
      old.seed != seed ||
      old.headAtRest != headAtRest ||
      old.divisions != divisions ||
      old.style != style ||
      !identical(old.wave, wave) ||
      !identical(old.waveFrom, waveFrom) ||
      old.mix != mix ||
      old.time != time ||
      old.music != music ||
      old.label?.text != label?.text;
}

/// Il mix che verra', per l'anteprima sull'onda della barra: dove sta, in
/// frazioni della barra, il colore e l'onda del brano che arriva, e il
/// volume che AutoMix dara' ai due lungo il mix.
@immutable
class SliderMixPreview {
  final double from;
  final double to;
  final Color color;

  /// L'onda dell'entrante, a [inRate] valori al secondo, e il tratto che ne
  /// suonera' nel mix: da [inStart] per [inSeconds] secondi.
  final List<double> inWave;
  final double inRate;
  final double inStart;
  final double inSeconds;

  /// Il volume dei due lungo il mix, 0-1, a passi uguali.
  final List<double> outGains;
  final List<double> inGains;

  const SliderMixPreview({
    required this.from,
    required this.to,
    required this.color,
    required this.inWave,
    required this.inRate,
    required this.inStart,
    required this.inSeconds,
    required this.outGains,
    required this.inGains,
  });

  double inLevelAt(double k) {
    if (inWave.isEmpty) return 0.22;
    final i = ((inStart + k * inSeconds) * inRate).floor();
    return inWave[i.clamp(0, inWave.length - 1)];
  }

  static double _at(List<double> g, double k) =>
      g.isEmpty ? 1 : g[(k * (g.length - 1)).round().clamp(0, g.length - 1)];

  double outGainAt(double k) => _at(outGains, k);
  double inGainAt(double k) => _at(inGains, k);

  @override
  bool operator ==(Object other) =>
      other is SliderMixPreview &&
      other.from == from &&
      other.to == to &&
      other.color == color &&
      identical(other.inWave, inWave) &&
      identical(other.outGains, outGains) &&
      identical(other.inGains, inGains);

  @override
  int get hashCode => Object.hash(from, to, color, inWave);
}
