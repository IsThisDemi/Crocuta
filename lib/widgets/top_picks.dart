import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/accent.dart';
import '../design/app_theme.dart';
import '../design/spot.dart';
import '../models/artist_names.dart';
import '../models/track.dart';
import '../providers.dart';
import 'content_width.dart';
import 'thumbnail.dart';

/// Un artista che ascolti spesso, con cio' che serve per la sua stazione.
class TopPick {
  final String artist;
  final String? artistId;

  /// Il suo brano che hai ascoltato di piu': ne presta la copertina, e fa
  /// da seme quando la pagina dell'artista non si puo' aprire.
  final Track seed;
  final int plays;

  const TopPick({
    required this.artist,
    required this.seed,
    required this.plays,
    this.artistId,
  });
}

/// Gli artisti piu' ascoltati, dalle statistiche. Nessuna richiesta di rete.
///
/// Si conta l'artista principale, non la riga intera: "Yeat & Nettspend"
/// e "Yeat" sono lo stesso Yeat, e contarli a parte lo dividerebbe in due
/// schede piu' deboli.
List<TopPick> topPicks({
  required Map<String, TrackStats> stats,
  required Iterable<Track> known,
  int limit = 6,
  int minPlays = 2,
}) {
  final byId = <String, Track>{};
  for (final t in known) {
    byId.putIfAbsent(t.id, () => t);
  }
  final plays = <String, int>{};
  final seed = <String, Track>{};
  final seedPlays = <String, int>{};
  final ids = <String, String>{};
  for (final e in stats.entries) {
    final t = byId[e.key];
    if (t == null) continue;
    final names = ArtistNames.splitArtists(t.author);
    if (names.isEmpty) continue;
    final a = names.first;
    plays[a] = (plays[a] ?? 0) + e.value.playCount;
    if (e.value.playCount > (seedPlays[a] ?? -1)) {
      seedPlays[a] = e.value.playCount;
      seed[a] = t;
    }
    if (t.artistId != null) ids.putIfAbsent(a, () => t.artistId!);
  }
  final sorted = plays.entries.where((e) => e.value >= minPlays).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in sorted.take(limit))
      TopPick(
        artist: e.key,
        artistId: ids[e.key],
        seed: seed[e.key]!,
        plays: e.value,
      ),
  ];
}

final topPicksProvider = Provider<List<TopPick>>((ref) {
  return topPicks(
    stats: ref.watch(statsProvider),
    known: [
      ...ref.watch(recentlyPlayedProvider),
      ...ref.watch(favoritesProvider),
    ],
  );
});

/// Le stazioni degli artisti che ascolti di piu', in fila.
class TopPicksRail extends ConsumerWidget {
  final List<TopPick> picks;

  const TopPicksRail({super.key, required this.picks});

  static const double _width = 196;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: _width + 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter + RailBleed.of(context),
        ),
        itemCount: picks.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
        itemBuilder: (_, i) => _PickCard(pick: picks[i], width: _width),
      ),
    );
  }
}

/// Una stazione: la macchia del brano che ne e' il seme, il nome
/// dell'artista grande sotto, e una macchia del colore della copertina col
/// tasto play, appoggiata sul bordo.
///
/// Niente pannello colorato dietro: era la scheda di Apple Music, e in
/// Macchia una macchia dentro un rettangolo perde la sua forma. Il colore
/// della stazione lo porta la macchia del play.
class _PickCard extends ConsumerStatefulWidget {
  final TopPick pick;
  final double width;

  const _PickCard({required this.pick, required this.width});

  @override
  ConsumerState<_PickCard> createState() => _PickCardState();
}

class _PickCardState extends ConsumerState<_PickCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final width = widget.width;
    final art = pick.seed.thumbnailUrl;
    final tint = toneMapAccent(ref.watch(vividColorProvider(art)).valueOrNull);
    void play() => ref
        .read(playerProvider.notifier)
        .playStation(seed: pick.seed, artistId: pick.artistId);

    return Semantics(
      button: true,
      label: '${pick.artist} Station',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: play,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: width,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        right: width * 0.08,
                        bottom: width * 0.08,
                        child: AnimatedScale(
                          scale: _hover ? 1.03 : 1,
                          duration: AppMotion.fast,
                          child: SpotThumbnail(url: art),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        width: width * 0.3,
                        height: width * 0.3,
                        child: SpotMotionBuilder(
                          builder: (context, t) => DecoratedBox(
                            decoration: ShapeDecoration(
                              color: tint,
                              shape: SpotBorder(
                                seed: '${pick.artist}#play',
                                time: t,
                              ),
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: AppColors.ink900,
                              size: width * 0.15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Il nome intero, stretto se serve ("passengerprincess" e'
                // una parola sola: tagliata diventava un altro nome).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    pick.artist,
                    maxLines: 1,
                    style: context.texts.headlineSmall,
                  ),
                ),
                Text(
                  'Station, based on your listening',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(color: tint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
