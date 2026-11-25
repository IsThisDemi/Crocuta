import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/motion.dart';
import '../design/spot.dart';
import '../providers.dart';
import '../screens/now_playing_screen.dart';
import 'artwork_hero.dart';
import 'spot_controls.dart';
import 'thumbnail.dart';
import 'track_tile.dart' show formatDuration;

/// Il brano in ascolto sopra le parole della navigazione, sul telefono.
///
/// Niente vetro: in Macchia la chrome e' nero pieno, e il colore lo portano
/// la copertina a macchia e il tasto play, che e' una macchia del colore del
/// brano. I gesti restano quelli di Apple Music: tocco o colpo verso l'alto
/// apre il player, di lato cambia brano.
class MiniPlayer extends ConsumerWidget {
  /// Se la copertina porta il tag del volo verso il player. Vedi
  /// [ArtworkHero]: ce ne puo' essere uno solo per volta.
  final bool hero;

  const MiniPlayer({super.key, this.hero = true});

  static const double height = 64;

  static void open(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(PlayerRoute<void>(builder: (_) => const NowPlayingScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Si osservano solo l'identita' del brano e i comandi: la posizione
    // cambia piu' volte al secondo e qui non serve, tranne che al filo di
    // avanzamento, che la osserva per conto suo.
    final track = ref.watch(playerProvider.select((s) => s.current));
    if (track == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isLoading = ref.watch(playerProvider.select((s) => s.isLoading));
    final player = ref.read(playerProvider.notifier);
    final colors = context.colors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Row(
            children: [
              ArtworkHero(
                url: track.thumbnailUrl,
                radius: AppRadius.xs,
                enabled: hero,
                child: SizedBox.square(
                  dimension: 46,
                  child: SpotThumbnail(url: track.thumbnailUrl, wobble: 0.7),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      track.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall?.copyWith(
                        color: colors.accentMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SpotPlayButton(
                playing: isPlaying,
                loading: isLoading,
                onPressed: player.toggle,
                size: 46,
              ),
              IconButton(
                icon: const Icon(Icons.fast_forward_rounded, size: 26),
                tooltip: 'Next',
                color: colors.textStrong,
                onPressed: player.next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il filo di avanzamento sopra il mini player: sottile, del colore del
/// brano, da bordo a bordo. E si trascina.
///
/// Fermo e' solo un filo. Col mouse sopra si ispessisce e mette in testa
/// una macchiolina; preso col dito o col mouse si gonfia, e sopra il punto
/// sale una goccia del colore del brano col tempo scritto dentro, attaccata
/// al filo da una gocciolina, come se la si stesse tirando fuori dalla
/// barra. Lasciato, cerca li' e la goccia rientra.
///
/// Il riquadro e' piu' alto del filo ([height]) perche' un filo di 2 punti
/// non si prende; il filo sta sul fondo, dove stava.
class MiniProgress extends ConsumerStatefulWidget {
  const MiniProgress({super.key});

  static const double height = 14;

  @override
  ConsumerState<MiniProgress> createState() => _MiniProgressState();
}

class _MiniProgressState extends ConsumerState<MiniProgress> {
  /// La frazione sotto il dito, mentre si trascina.
  double? _drag;
  bool _hover = false;

  static const _drop = Size(66, 38);

  void _grab(double x, double width) {
    final f = (x / width).clamp(0.0, 1.0);
    if (_drag == null) HapticFeedback.selectionClick();
    setState(() => _drag = f);
  }

  void _release() {
    final f = _drag;
    if (f == null) return;
    final total = ref.read(playerProvider).duration.inMilliseconds;
    if (total > 0) {
      ref
          .read(playerProvider.notifier)
          .seek(Duration(milliseconds: (f * total).round()));
    }
    setState(() => _drag = null);
  }

  void _cancel() => setState(() => _drag = null);

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    // Durante un mix suonano due brani: non c'e' un punto da cercare.
    final mixing = ref.watch(playerProvider.select((s) => s.mixing));
    final total = duration.inMilliseconds;
    final live = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    final canSeek = total > 0 && !mixing;
    final dragging = _drag != null;
    final f = _drag ?? live;
    final accent = context.colors.accent;
    final thick = dragging ? 6.0 : (_hover && canSeek ? 4.0 : 2.0);

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final x = f * w;
        return MouseRegion(
          cursor: canSeek ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: canSeek ? (d) => _grab(d.localPosition.dx, w) : null,
            onTapUp: canSeek ? (_) => _release() : null,
            onTapCancel: _cancel,
            onHorizontalDragStart: canSeek
                ? (d) => _grab(d.localPosition.dx, w)
                : null,
            onHorizontalDragUpdate: canSeek
                ? (d) => _grab(d.localPosition.dx, w)
                : null,
            onHorizontalDragEnd: canSeek ? (_) => _release() : null,
            onHorizontalDragCancel: _cancel,
            child: SizedBox(
              height: MiniProgress.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Il resto del brano: compare solo quando il filo si
                  // ispessisce, per dire fin dove si puo' andare.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      height: thick,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: thick > 2 ? 0.12 : 0,
                        ),
                        borderRadius: BorderRadius.circular(thick),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: x,
                    child: AnimatedContainer(
                      duration: dragging ? Duration.zero : AppMotion.fast,
                      height: thick,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(thick),
                        ),
                      ),
                    ),
                  ),
                  // La testa: una macchiolina dove arriva il brano.
                  Positioned(
                    left: x - 7,
                    bottom: thick / 2 - 7,
                    width: 14,
                    height: 14,
                    child: AnimatedScale(
                      scale: (_hover && canSeek) || dragging ? 1 : 0,
                      duration: AppMotion.fast,
                      curve: Curves.easeOutBack,
                      child: LiveSpotDot(color: accent, seed: 'seek-head'),
                    ),
                  ),
                  // La goccia col tempo, e la gocciolina che la tiene al
                  // filo. Crescono dal filo verso l'alto.
                  Positioned(
                    left: x - 4,
                    bottom: thick + 2,
                    width: 8,
                    height: 8,
                    child: AnimatedScale(
                      scale: dragging ? 1 : 0,
                      duration: AppMotion.fast,
                      curve: Curves.easeOutBack,
                      child: LiveSpotDot(color: accent, seed: 'seek-neck'),
                    ),
                  ),
                  Positioned(
                    left: (x - _drop.width / 2).clamp(
                      4.0,
                      math.max(4.0, w - _drop.width - 4),
                    ),
                    bottom: thick + 8,
                    width: _drop.width,
                    height: _drop.height,
                    child: IgnorePointer(
                      child: AnimatedScale(
                        scale: dragging ? 1 : 0,
                        alignment: Alignment.bottomCenter,
                        duration: const Duration(milliseconds: 260),
                        curve: dragging ? Curves.easeOutBack : Curves.easeIn,
                        child: TimeDrop(
                          text: formatDuration(
                            Duration(milliseconds: (f * total).round()),
                          ),
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
  }
}

/// La goccia col tempo che sale mentre si cerca un punto del brano: qui
/// sopra il filo, nella barra del telefono sopra la copertina.
class TimeDrop extends StatelessWidget {
  final String text;
  final Color color;

  const TimeDrop({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return SpotMotionBuilder(
      builder: (context, t) => DecoratedBox(
        decoration: ShapeDecoration(
          color: color,
          shadows: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
          shape: SpotBorder(
            seed: 'seek-drop',
            wobble: 0.7,
            time: t == null ? null : t * 2.2,
            music: SpotMotion.musicOf(context),
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: context.texts.titleMedium?.copyWith(
              color: AppColors.ink900,
              fontWeight: FontWeight.w800,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ),
      ),
    );
  }
}
