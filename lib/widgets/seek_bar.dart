import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/accent.dart';
import '../providers.dart';
import '../services/mix_info.dart';

/// The playback scrubber, with elapsed and remaining time.
///
/// Replaces the package's glass slider, which drew its own translucent track
/// and ignored the app theme: elapsed and remaining looked identical, so the
/// bar showed a thumb but communicated no progress.
///
/// Holds the drag position locally while scrubbing. Seeking on every
/// onChanged fought the position stream, making the thumb jump back under
/// the finger.
class SeekBar extends ConsumerStatefulWidget {
  /// Senza i margini laterali: la barra va da bordo a bordo del suo spazio,
  /// allineata al testo sopra. Per la tana, dove la colonna e' stretta.
  final bool dense;

  const SeekBar({super.key, this.dense = false});

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _dragging;

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

    final total = duration.inMilliseconds.toDouble();
    final live = position.inMilliseconds.toDouble().clamp(0.0, total);
    final value = _dragging ?? live;
    final accent = context.colors.accent;

    final numeric = context.texts.bodySmall?.copyWith(
      color: context.colors.textMuted,
      fontFeatures: AppTypography.tabular,
    );

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: accent,
            // Clearly darker than the accent, so the split between played
            // and remaining is visible at a glance.
            inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.18),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            padding: widget.dense
                ? const EdgeInsets.symmetric(vertical: 12)
                : null,
            value: total <= 0 ? 0 : value,
            max: total <= 0 ? 1 : total,
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

/// La barra durante un mix AutoMix: i due brani che si passano la mano.
///
/// Prima era la barra piena nel colore del brano, con un riflesso bianco:
/// diceva "sta mixando" ma non verso cosa. Ora il colore del brano
/// che esce cede a quello del brano che entra, col mix: la fascia dove si
/// mescolano avanza da sinistra a destra, e la scritta sotto prende il
/// colore dei due mescolati. Un bagliore dei due colori sotto la barra la
/// fa sembrare viva.
class _MixingBar extends ConsumerStatefulWidget {
  final bool dense;

  const _MixingBar({this.dense = false});

  @override
  ConsumerState<_MixingBar> createState() => _MixingBarState();
}

class _MixingBarState extends ConsumerState<_MixingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  /// Quanto e' larga la fascia in cui i due colori si mescolano.
  static const _blend = 0.35;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mix = ref.watch(mixInfoProvider);
    final accent = context.colors.accent;
    final from = mix == null
        ? accent
        : ref.watch(artworkAccentProvider(mix.from.thumbnailUrl)).valueOrNull ??
              accent;
    final to = mix == null
        ? accent
        : ref.watch(artworkAccentProvider(mix.to.thumbnailUrl)).valueOrNull ??
              accent;
    final p = mix?.progress ?? 0.5;
    // Il centro della fascia: da appena fuori a sinistra ad appena fuori a
    // destra, cosi' ai due capi del mix c'e' un colore solo.
    final mid = -_blend / 2 + p * (1 + _blend);
    final both = Color.lerp(from, to, p)!;

    return Column(
      children: [
        // Stessa altezza dello slider, cosi' niente sotto si sposta.
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  // Un'onda di luce che scorre sempre, piano: il mix e' in
                  // corso anche quando la fascia si muove poco.
                  final wave = -0.2 + _c.value * 1.4;
                  return Container(
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: both.withValues(alpha: 0.55),
                          blurRadius: 12,
                        ),
                      ],
                      gradient: LinearGradient(
                        colors: [to, to, from, from],
                        stops: [
                          0,
                          (mid - _blend / 2).clamp(0.0, 1.0),
                          (mid + _blend / 2).clamp(0.0, 1.0),
                          1,
                        ],
                      ),
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.45),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: [
                          (wave - 0.12).clamp(0.0, 1.0),
                          wave.clamp(0.0, 1.0),
                          (wave + 0.12).clamp(0.0, 1.0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 0 : AppSpacing.lg,
          ),
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

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
