import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../models/track.dart';
import '../providers.dart';
import 'artwork_pressable.dart';
import 'content_width.dart';
import 'thumbnail.dart';
import 'track_context_menu.dart';

/// Un video della ricerca: il fotogramma largo, a macchia come ogni
/// copertina dell'app, con la durata sopra, il titolo su due righe e sotto
/// chi l'ha pubblicato e quante volte e' stato visto.
///
/// Toccandolo si ascolta, come una canzone: e' il motivo per cui c'e' (un
/// remix uscito solo su YouTube). Il clic destro, il tocco lungo o "…"
/// aprono il menu del brano, dove si salva, si mette in coda o si guarda.
class VideoCard extends ConsumerWidget {
  final Track video;
  final VoidCallback onTap;
  final double width;

  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.width = 248,
  });

  /// Le proporzioni del fotogramma: quelle di YouTube.
  static const double aspect = 16 / 9;

  String get _subtitle => [
    video.author,
    if (video.playsShort case final views?) '$views views',
  ].join(' · ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(
      playerProvider.select((s) => s.current?.id == video.id),
    );
    final height = width / aspect;
    final shape = SpotBorder(seed: video.thumbnailUrl, wobble: 0.55);

    void menu(Offset? at) =>
        showTrackMenu(context, ref, video, globalPosition: at);

    return SizedBox(
      width: width,
      child: GestureDetector(
        onSecondaryTapUp: (d) => menu(d.globalPosition),
        child: ArtworkPressable(
          onTap: onTap,
          onLongPress: () => menu(null),
          builder: (context, state) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SpotMotionBuilder(
                  builder: (context, t) => PressableArtwork(
                    state: state,
                    shape: shape.copyWith(
                      time: t,
                      music: SpotMotion.musicOf(context),
                    ),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Spot(
                            seed: video.thumbnailUrl,
                            wobble: 0.55,
                            rim: Colors.white.withValues(alpha: 0.08),
                            child: Thumbnail(url: video.thumbnailUrl),
                          ),
                          // Dentro la macchia e lontano dal bordo, che ha
                          // lobi e rientranze: in un angolo si taglierebbe.
                          Positioned(
                            right: width * 0.13,
                            bottom: height * 0.15,
                            child: _Badge(
                              isCurrent: isCurrent,
                              duration: video.duration,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall?.copyWith(
                    color: isCurrent ? context.colors.accent : null,
                  ),
                ),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.accentMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La durata, o l'equalizzatore quando il video e' quello che suona.
class _Badge extends StatelessWidget {
  final bool isCurrent;
  final Duration? duration;

  const _Badge({required this.isCurrent, required this.duration});

  @override
  Widget build(BuildContext context) {
    final d = duration;
    if (!isCurrent && d == null) return const SizedBox.shrink();
    final text = d == null
        ? null
        : '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent) ...[
            Icon(
              Icons.graphic_eq_rounded,
              size: 13,
              color: context.colors.accent,
            ),
            if (text != null) const SizedBox(width: 4),
          ],
          if (text != null)
            Text(
              text,
              style: context.texts.labelSmall?.copyWith(
                color: Colors.white,
                fontFeatures: AppTypography.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

/// La fila dei video, con i margini delle altre file della pagina.
class VideoRail extends StatelessWidget {
  final List<Track> videos;
  final void Function(Track video) onPlay;

  const VideoRail({super.key, required this.videos, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    // Sul telefono un po' piu' stretti, perche' se ne veda spuntare un
    // secondo: e' il segno che la fila scorre.
    final width = MediaQuery.sizeOf(context).width < 600 ? 232.0 : 264.0;
    // Fotogramma + titolo su due righe + sottotitolo, come MediaCardRail.
    final height = width / VideoCard.aspect + 84;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter + RailBleed.of(context),
        ),
        itemCount: videos.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, i) => VideoCard(
          video: videos[i],
          width: width,
          onTap: () => onPlay(videos[i]),
        ),
      ),
    );
  }
}
