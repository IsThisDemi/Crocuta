import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../models/track.dart';
import '../providers.dart';
import 'thumbnail.dart';

/// Il tasto play di Macchia: una macchia piena del colore del brano.
///
/// La forma e' sempre la stessa (il seme e' fisso): e' un comando, deve
/// farsi riconoscere a colpo d'occhio, non cambiare a ogni canzone come le
/// copertine.
class SpotPlayButton extends StatelessWidget {
  final bool playing;
  final bool loading;
  final VoidCallback? onPressed;
  final double size;

  const SpotPlayButton({
    super.key,
    required this.playing,
    this.loading = false,
    this.onPressed,
    this.size = 56,
  });

  static const _seed = 'crocuta-play';

  @override
  Widget build(BuildContext context) {
    // La macchia del play respira come tutte le altre.
    return SpotMotionBuilder(builder: _build);
  }

  Widget _build(BuildContext context, double? t) {
    final accent = context.colors.accent;
    final shape = SpotBorder(
      seed: _seed,
      wobble: 0.9,
      time: t == null ? null : t * 1.4,
      music: SpotMotion.musicOf(context),
    );
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: Tooltip(
        message: playing ? 'Pause' : 'Play',
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: accent,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: shape,
              onTap: loading ? null : onPressed,
              child: Center(
                child: loading
                    ? SizedBox.square(
                        dimension: size * 0.34,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.ink900,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: size * 0.5,
                        color: AppColors.ink900,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una copertina a macchia con attorno le macchie "satellite": piccole
/// macchie dei colori della copertina, come schizzate via da lei.
///
/// Il riquadro del widget e' quello della copertina; i satelliti escono dai
/// bordi (il genitore deve lasciargli spazio, o accettare che vengano
/// tagliati). Le loro posizioni sono fisse in proporzione e variano solo un
/// poco col brano, cosi' la composizione resta bilanciata.
class SpotCover extends ConsumerWidget {
  final String url;
  final double size;
  final bool hiRes;

  /// Quanti satelliti, da 0 a 4.
  final int satellites;

  /// Al posto della copertina semplice: il player ci mette il videoclip in
  /// loop e i gesti. Viene ritagliato a macchia qui.
  final Widget? child;

  /// Larghezza su altezza: 1 per una copertina, 16/9 per un videoclip.
  /// [size] e' l'altezza; i satelliti stanno attorno al bordo destro e in
  /// basso a sinistra come sempre, misurati sull'altezza.
  final double aspect;

  /// Quanto si allontana dal cerchio (vedi [SpotBorder.wobble]). Un video
  /// la vuole piu' tonda: i lobi taglierebbero l'immagine.
  final double wobble;

  const SpotCover({
    super.key,
    required this.url,
    required this.size,
    this.hiRes = false,
    this.satellites = 4,
    this.child,
    this.aspect = 1,
    this.wobble = 1,
  });

  /// Centro e diametro di ogni satellite, in frazioni del lato.
  static const _layout = [
    (dx: 1.08, dy: 0.10, d: 0.28),
    (dx: 1.14, dy: 0.40, d: 0.14),
    (dx: 1.04, dy: 0.60, d: 0.07),
    (dx: -0.07, dy: 0.90, d: 0.09),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.colors.accent;
    final swatches = url.isEmpty
        ? const <Color>[]
        : ref
              .watch(artworkPaletteProvider(url))
              .maybeWhen(
                data: (p) => p.swatches,
                orElse: () => const <Color>[],
              );
    Color colorFor(int i) {
      if (swatches.isEmpty) {
        return Color.lerp(accent, Colors.black, i * 0.18)!;
      }
      return swatches[i % swatches.length];
    }

    final jitter = (spotSeed(url) % 7 - 3) / 100;

    final width = size * aspect;
    return Builder(
      builder: (context) => SizedBox(
        width: width,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < satellites.clamp(0, 4); i++)
              // I satelliti fluttuano attorno al loro posto, ognuno col suo
              // giro (ritmo e fase dal seme), come gocce che galleggiano
              // vicino alla copertina; e intanto si deformano piu' svelti
              // di lei: le gocce piccole si muovono piu' delle grandi.
              Positioned(
                // Quelli a destra seguono il bordo destro, quello in basso
                // a sinistra il sinistro.
                left:
                    (_layout[i].dx > 0.5 ? width - size : 0) +
                    size * (_layout[i].dx + jitter) -
                    size * _layout[i].d / 2,
                top: size * (_layout[i].dy - jitter) - size * _layout[i].d / 2,
                width: size * _layout[i].d,
                height: size * _layout[i].d,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: colorFor(i)),
                  duration: AppMotion.slow,
                  builder: (_, c, _) => SpotMotionBuilder(
                    builder: (_, t) {
                      final rnd = SpotRandom(spotSeed('$url#orbit$i'));
                      final phase = rnd.nextDouble() * 2 * math.pi;
                      final speed = 0.35 + rnd.nextDouble() * 0.3;
                      final reach = size * (0.025 + _layout[i].d * 0.12);
                      final offset = t == null
                          ? Offset.zero
                          : Offset(
                              reach *
                                  (math.sin(t * speed + phase) -
                                      math.sin(phase)),
                              reach *
                                  (math.cos(t * speed * 0.8 + phase) -
                                      math.cos(phase)),
                            );
                      return Transform.translate(
                        offset: offset,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: c,
                            shape: SpotBorder(
                              seed: '$url#$i',
                              wobble: 0.8,
                              time: t == null ? null : t * (1.3 + i * 0.15),
                              music: SpotMotion.musicOf(context),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            Positioned.fill(
              child: child == null
                  ? SpotThumbnail(url: url, hiRes: hiRes, wobble: wobble)
                  : Spot(
                      seed: url,
                      wobble: wobble,
                      rim: Colors.white.withValues(alpha: 0.08),
                      child: child!,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Riproduci e casuale per una raccolta di brani: la macchia del play e,
/// accanto, "Shuffle" come parola. Lo stesso gruppo in ogni pagina che si
/// ascolta per intero (album, playlist, classifiche).
class SpotPlayRow extends ConsumerWidget {
  final List<Track> tracks;
  final double size;

  const SpotPlayRow({super.key, required this.tracks, this.size = 64});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider.notifier);
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpotPlayButton(
          playing: false,
          size: size,
          onPressed: tracks.isEmpty
              ? null
              : () {
                  player.setShuffle(false);
                  player.playTrack(tracks.first, queue: tracks);
                },
        ),
        const SizedBox(width: AppSpacing.md),
        TextButton.icon(
          onPressed: tracks.isEmpty
              ? null
              : () {
                  player.setShuffle(true);
                  final start = tracks[math.Random().nextInt(tracks.length)];
                  player.playTrack(start, queue: tracks);
                },
          style: TextButton.styleFrom(
            foregroundColor: colors.textStrong,
            textStyle: context.texts.titleMedium,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          icon: Icon(Icons.shuffle_rounded, size: 22, color: colors.accent),
          label: const Text('Shuffle'),
        ),
      ],
    );
  }
}

/// Una macchiolina piena di [color] che respira mentre la musica suona: il
/// segno accanto alla sezione attiva, nella tana e nella barra del
/// telefono.
class LiveSpotDot extends ConsumerWidget {
  final Color color;
  final String seed;

  const LiveSpotDot({super.key, required this.color, this.seed = 'den-marker'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpotMotionBuilder(
      builder: (context, t) => DecoratedBox(
        decoration: ShapeDecoration(
          color: color,
          shape: SpotBorder(
            seed: seed,
            time: t == null ? null : t * 1.8,
            music: SpotMotion.musicOf(context),
          ),
        ),
      ),
    );
  }
}
