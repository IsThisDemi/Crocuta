import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/accent.dart';
import '../design/spot.dart';
import '../providers.dart';
import '../services/automix.dart' show MixStage;
import '../services/mix_info.dart';
import 'spot_slider.dart';

/// The playback scrubber, with elapsed and remaining time.
///
/// La barra e' una [SpotSlider] a onda: l'onda del brano, accesa fin dove
/// si e' arrivati, e tenendola la goccia col tempo. Con AutoMix sotto
/// l'onda c'e' il segno di dove partira' il mix, e durante il mix la barra
/// mostra i due brani che si incrociano ([_MixingBar]).
///
/// Holds the drag position locally while scrubbing. Seeking on every
/// onChanged fought the position stream, making the thumb jump back under
/// the finger.
class SeekBar extends ConsumerStatefulWidget {
  /// Senza i margini laterali: la barra va da bordo a bordo del suo spazio,
  /// allineata al testo sopra. Per la tana, dove la colonna e' stretta.
  final bool dense;

  const SeekBar({super.key, this.dense = false});

  /// L'altezza della barra senza i tempi: la stessa col mix in corso, cosi'
  /// niente sotto si sposta.
  static double barHeight({bool dense = false}) => dense ? 32 : 40;

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _dragging;

  /// L'anteprima del mix, rifatta solo quando cambia il piano: le liste
  /// restano le stesse e la barra non ridisegna a ogni passo.
  SliderMixPreview? _cachedPreview;
  MixPlanInfo? _previewOf;
  double _previewSeconds = 0;

  SliderMixPreview _preview(MixPlanInfo plan, double seconds, Color color) {
    final cached = _cachedPreview;
    if (cached != null &&
        identical(plan, _previewOf) &&
        seconds == _previewSeconds &&
        cached.color == color) {
      return cached;
    }
    double loudness(MixStage s) {
      final a = s.audible;
      return (a.low + a.mid + a.high) / 3;
    }

    _previewOf = plan;
    _previewSeconds = seconds;
    return _cachedPreview = SliderMixPreview(
      from: (plan.outStart / seconds).clamp(0.0, 1.0),
      to: ((plan.outStart + plan.length) / seconds).clamp(0.0, 1.0),
      color: color,
      inWave: plan.toWave,
      inRate: plan.waveRate,
      inStart: plan.inStart,
      inSeconds: plan.length * plan.inPerOut,
      outGains: [for (final s in plan.outStages) loudness(s)],
      inGains: [for (final s in plan.inStages) loudness(s)],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Durante una transizione di AutoMix non c'e' un punto da cercare: due
    // brani suonano insieme. Come in Apple, la barra si riempie e dice che
    // sta mixando.
    if (ref.watch(playerProvider.select((s) => s.mixing))) {
      return _MixingBar(dense: widget.dense);
    }
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final position = ref.watch(playerProvider.select((s) => s.position));
    final currentId = ref.watch(playerProvider.select((s) => s.current?.id));
    final wave = ref.watch(waveformProvider);
    final plan = ref.watch(mixPlanProvider);
    final mixColor = plan == null
        ? null
        : ref.watch(artworkAccentProvider(plan.to.thumbnailUrl)).valueOrNull;

    final total = duration.inMilliseconds.toDouble();
    final live = position.inMilliseconds.toDouble().clamp(0.0, total);
    final value = _dragging ?? live;
    final seconds = total / 1000;
    final mix = plan != null && plan.fromId == currentId && seconds > 0
        ? _preview(plan, seconds, mixColor ?? context.colors.accent)
        : null;
    final numeric = context.texts.bodySmall?.copyWith(
      color: context.colors.textMuted,
      fontFeatures: AppTypography.tabular,
    );

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 0 : AppSpacing.lg,
          ),
          child: SpotSlider(
            seed: 'seek',
            style: SpotSliderStyle.wave,
            wave: wave != null && wave.trackId == currentId
                ? wave.levels
                : null,
            mix: mix,
            height: SeekBar.barHeight(dense: widget.dense),
            value: total <= 0 ? 0 : value,
            max: total <= 0 ? 1 : total,
            label: (v) => _fmt(Duration(milliseconds: v.round())),
            semanticLabel: 'Position',
            semanticValue: (v) => _fmt(Duration(milliseconds: v.round())),
            onChanged: total <= 0 ? null : (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              ref
                  .read(playerProvider.notifier)
                  .seek(Duration(milliseconds: v.round()));
              setState(() => _dragging = null);
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 0 : AppSpacing.lg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(Duration(milliseconds: value.round())), style: numeric),
              Text(
                total <= 0
                    ? '--:--'
                    // Remaining, the way music players show it.
                    : '-${_fmt(Duration(milliseconds: (total - value).round()))}',
                style: numeric,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La barra durante un mix AutoMix: i due brani che si passano la mano,
/// dal vivo.
///
/// La barra e' il tratto del mix, dall'inizio alla fine, come due deck:
/// sopra la riga il brano che esce, nel suo colore, sotto quello che entra,
/// nel suo. Ogni barretta e' divisa in bassi (scuri, vicino alla riga),
/// medi e acuti (chiari, fuori), ognuno alto quanto suona in quel punto del
/// brano per quanto lo lascia passare AutoMix — equalizzatore, filtri,
/// volume. Si vedono i bassi che passano dall'uno all'altro, i filtri che
/// chiudono, l'eco che si allontana, e un filo per la voce di ognuno
/// finche' canta. Fin dove il mix e' arrivato le barrette sono accese, e un
/// taglio bianco segna il punto. Sotto, solo "AutoMix", nel colore dei
/// due mescolati.
class _MixingBar extends ConsumerWidget {
  final bool dense;

  const _MixingBar({this.dense = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mix = ref.watch(mixInfoProvider);
    final plan = ref.watch(mixPlanProvider);
    final accent = context.colors.accent;
    final from = mix == null
        ? accent
        : ref.watch(artworkAccentProvider(mix.from.thumbnailUrl)).valueOrNull ??
              accent;
    final to = mix == null
        ? accent
        : ref.watch(artworkAccentProvider(mix.to.thumbnailUrl)).valueOrNull ??
              accent;
    final p = mix?.progress ?? 0;
    final both = Color.lerp(from, to, p)!;
    // Il piano e' quello di questo mix solo se va verso lo stesso brano.
    final matching = plan != null && mix != null && plan.to.id == mix.to.id
        ? plan
        : null;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 0 : AppSpacing.lg),
          child: SizedBox(
            height: SeekBar.barHeight(dense: dense),
            width: double.infinity,
            child: CustomPaint(
              painter: _MixPainter(
                plan: matching,
                progress: p,
                from: from,
                to: to,
                time: SpotMotion.of(context),
                music: SpotMotion.musicListenableOf(context),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 0 : AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.multitrack_audio_rounded, size: 14, color: both),
              const SizedBox(width: 4),
              Text(
                'AutoMix',
                style: context.texts.bodySmall?.copyWith(
                  color: both,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MixPainter extends CustomPainter {
  final MixPlanInfo? plan;
  final double progress;
  final Color from;
  final Color to;
  final ValueListenable<double>? time;
  final ValueListenable<SpotMusic>? music;

  _MixPainter({
    required this.plan,
    required this.progress,
    required this.from,
    required this.to,
    required this.time,
    required this.music,
  }) : super(repaint: Listenable.merge([time, music]));

  /// La banda [v] al secondo [sec], a [rate] valori al secondo.
  static double _at(List<double> v, double rate, double sec) {
    if (v.isEmpty) return 0.5;
    final x = (sec * rate).clamp(0.0, v.length - 1.0);
    final i = x.floor();
    final j = math.min(i + 1, v.length - 1);
    return v[i] + (v[j] - v[i]) * (x - i);
  }

  static Color _shade(Color c, double k) => k < 0
      ? Color.lerp(c, Colors.black, -k)!
      : Color.lerp(c, Colors.white, k)!;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    final m = music?.value ?? silentMusic;
    final bass = m.pulse.clamp(0.0, 2.0);
    final x = progress * w;
    final pl = plan;

    const pitch = 6.0;
    final count = math.max(8, (w / pitch).floor());
    final step = w / count;
    final bar = math.min(3.4, step * 0.58);
    // Ogni corsia (sopra chi esce, sotto chi entra) e' alta al massimo
    // tanto, e le tre bande si spartiscono l'altezza.
    final lane = math.min(15.0, size.height / 2 - 5);
    const gap = 0.6;

    for (var i = 0; i < count; i++) {
      final u = (i + 0.5) / count;
      final cx = (i + 0.5) * step;
      final lit = cx <= x;
      final near = math.exp(-(cx - x).abs() / 60);
      final jump = 1 + 0.35 * bass * near;
      for (final up in [true, false]) {
        final stages = pl == null ? null : (up ? pl.outStages : pl.inStages);
        // Senza il piano: una dissolvenza qualunque.
        final stage = stages == null
            ? MixStage(
                volume: up
                    ? math.cos(u * math.pi / 2)
                    : math.sin(u * math.pi / 2),
              )
            : MixPlanInfo.stageAt(stages, u);
        final g = stage.audible;
        final bands = pl == null ? null : (up ? pl.fromBands : pl.toBands);
        final sec = pl == null
            ? 0.0
            : up
            ? pl.outStart + u * pl.length
            : pl.inStart + u * pl.length * pl.inPerOut;
        final rate = pl?.bandRate ?? 2;
        final lo = bands == null ? 0.6 : _at(bands.low, rate, sec);
        final mi = bands == null ? 0.6 : _at(bands.mid, rate, sec);
        final hi = bands == null ? 0.6 : _at(bands.high, rate, sec);
        final c = up ? from : to;
        // Dalla riga verso fuori: bassi (scuri), medi, acuti (chiari).
        // Ognuna ha la sua parte della corsia (i bassi la piu' grande):
        // insieme non escono mai, e il filo della voce resta libero. Una
        // barretta sola, arrotondata, con le tre bande di colore dentro.
        final segs = [
          for (final (level, gain, color, share) in [
            (lo, g.low, _shade(c, -0.45), 0.42),
            (mi, g.mid, c, 0.34),
            (hi, g.high, _shade(c, 0.5), 0.24),
          ])
            (
              lane * share * (0.2 + 0.8 * level) * gain * math.min(jump, 1.15),
              color,
            ),
        ];
        final total = segs.fold(0.0, (a, e) => a + e.$1);
        if (total >= 0.8) {
          final shape = RRect.fromRectAndRadius(
            up
                ? Rect.fromLTWH(cx - bar / 2, cy - gap - total, bar, total)
                : Rect.fromLTWH(cx - bar / 2, cy + gap, bar, total),
            Radius.circular(math.min(bar, total) / 2),
          );
          canvas
            ..save()
            ..clipRRect(shape);
          var y = up ? cy - gap : cy + gap;
          for (final (h, color) in segs) {
            if (h <= 0) continue;
            canvas.drawRect(
              up
                  ? Rect.fromLTWH(cx - bar, y - h, bar * 2, h)
                  : Rect.fromLTWH(cx - bar, y, bar * 2, h),
              Paint()..color = color.withValues(alpha: lit ? 1 : 0.33),
            );
            y = up ? y - h : y + h;
          }
          canvas.restore();
        }
        // L'eco sull'uscente: ripetizioni sempre piu' piccole che si
        // allontanano.
        if (up && stage.echo > 0.04 && i % 3 == 0) {
          for (var k = 1; k <= 3; k++) {
            final gx = cx + k * step * 1.4;
            if (gx > w) break;
            canvas.drawCircle(
              Offset(gx, cy - lane * (0.55 + 0.15 * k)),
              1.4 * stage.echo / k + 0.4,
              Paint()
                ..color = c.withValues(
                  alpha: (lit ? 0.8 : 0.35) * stage.echo / k,
                ),
            );
          }
        }
      }
    }

    // La voce: un filo sopra chi esce finche' canta, e sotto chi entra da
    // quando tocca a lui. Solo se le voci si incontrano nel mix.
    final off = pl?.voiceOff;
    if (pl != null && off != null) {
      final swap = pl.voiceSwap ?? off;
      void voice(double a, double b, double yy, Color c) {
        if (b <= a) return;
        final r = Rect.fromLTRB(a * w, yy - 1, b * w, yy + 1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(1)),
          Paint()..color = c.withValues(alpha: 0.85),
        );
      }

      voice(0, off, cy - lane - 3, from);
      voice(swap, 1, cy + lane + 3, to);
    }

    // Il punto del mix.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: 3, height: lane * 2 + 8),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_MixPainter old) =>
      old.plan != plan ||
      old.progress != progress ||
      old.from != from ||
      old.to != to ||
      old.time != time ||
      old.music != music;
}

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
