import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../design/chrome.dart';
import '../navigation.dart';
import '../providers.dart';
import '../services/replay.dart';
import '../widgets/content_width.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/empty_state.dart';
import '../widgets/large_title.dart';
import '../widgets/media_card.dart';
import '../widgets/section_header.dart';
import '../widgets/thumbnail.dart';
import 'replay_story.dart';
import '../widgets/spot_controls.dart';

/// "188 minuti" e' un'unita' grezza: sono tre ore e otto.
String listeningTime(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Le statistiche, con la forma di Replay di Apple Music.
///
/// In cima il tempo ascoltato, grande: e' il numero che si viene a
/// guardare. Poi la classifica come playlist da ascoltare, gli artisti come
/// facce, i dischi come copertine. E il periodo si sceglie — settimana,
/// mese, anno, sempre — invece di un totale unico dal primo giorno.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  ReplayPeriod _period = ReplayPeriod.allTime;

  @override
  Widget build(BuildContext context) {
    final replay = ref.watch(replayProvider(_period));
    final start = _period.start(DateTime.now());
    final since = replay.countingSince;
    // Il registro dei singoli ascolti e' nato dopo il periodo scelto: il
    // mese c'e', ma solo in parte, e va detto.
    final partial = start != null && (since == null || since.isAfter(start));
    final topTracks = [for (final r in replay.tracks) r.track];

    return DetailScaffold(
      body: CollapsingTitleFrame(
        title: 'Stats',
        barOffset: DetailScaffold.backButtonOffset,
        child: ContentWidth(
          maxWidth: ContentWidth.wide,
          child: ListView(
            padding: EdgeInsets.only(
              top: topBarInset(context) - AppSpacing.md,
              bottom: listBottomPadding(context, ref),
            ),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  AppSpacing.md,
                ),
                child: LargeTitle('Stats'),
              ),
              _PeriodPicker(
                value: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
              _Hero(
                replay: replay,
                note: partial
                    ? since == null
                          ? 'Plays are counted from now on'
                          : 'Counting since ${_months[since.month - 1]} '
                                '${since.day}'
                    : null,
              ),
              if (replay.tracks.isNotEmpty)
                _ReplayEntry(period: _period, replay: replay),
              if (replay.tracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyState(
                    icon: Icons.bar_chart_rounded,
                    title: 'Nothing played ${_period.phrase}',
                  ),
                )
              else ...[
                // La classifica e' una playlist, come Replay: si ascolta.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
                    AppSpacing.gutter,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SpotPlayRow(tracks: topTracks),
                  ),
                ),
                const SectionHeader(title: 'Top songs'),
                for (var i = 0; i < replay.tracks.length && i < 10; i++)
                  _SongRow(
                    rank: i + 1,
                    entry: replay.tracks[i],
                    queue: topTracks,
                  ),
                if (replay.artists.isNotEmpty) ...[
                  const SectionHeader(title: 'Top artists'),
                  _ArtistRail(artists: replay.artists),
                ],
                if (replay.albums.isNotEmpty) ...[
                  const SectionHeader(title: 'Top albums'),
                  MediaCardRail(
                    itemCount: replay.albums.length,
                    itemBuilder: (_, i) {
                      final a = replay.albums[i];
                      return MediaCard(
                        imageUrl: a.album.thumbnailUrl,
                        title: a.album.title,
                        subtitle:
                            '${a.album.subtitle} · ${a.plays} play${a.plays == 1 ? '' : 's'}',
                        onTap: () => openAlbum(
                          context,
                          a.album.browseId,
                          title: a.album.title,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Settimana, mese, anno, sempre: quattro parole, quella scelta chiara con
/// la macchia del colore del brano davanti, le altre spente. Lo stesso
/// segno della navigazione.
class _PeriodPicker extends StatelessWidget {
  final ReplayPeriod value;
  final ValueChanged<ReplayPeriod> onChanged;

  const _PeriodPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      // Una riga sola, che si stringe se non ci sta: a capo, su un telefono
      // stretto, "All Time" finiva da solo sotto le altre tre.
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.lg,
            children: [
              for (final p in ReplayPeriod.values)
                Semantics(
                  button: true,
                  selected: p == value,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(p),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            scale: p == value ? 1 : 0,
                            duration: AppMotion.base,
                            curve: AppMotion.emphasised,
                            child: SizedBox.square(
                              dimension: 10,
                              child: SpotMotionBuilder(
                                builder: (context, t) => DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: colors.accent,
                                    shape: SpotBorder(
                                      seed: 'den-marker',
                                      time: t,
                                      music: SpotMotion.musicOf(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedDefaultTextStyle(
                            duration: AppMotion.fast,
                            style: context.texts.headlineSmall!.copyWith(
                              fontSize: 26,
                              color: p == value
                                  ? colors.textStrong
                                  : colors.accentMuted.withValues(alpha: 0.7),
                            ),
                            child: Text(p.label),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'ingresso al Replay raccontato: le prime copertine a ventaglio e il
/// periodo, come la scheda di Replay in Apple Music.
class _ReplayEntry extends StatelessWidget {
  final ReplayPeriod period;
  final ReplaySummary replay;

  const _ReplayEntry({required this.period, required this.replay});

  @override
  Widget build(BuildContext context) {
    final covers = [
      for (final t in replay.tracks) t.track.thumbnailUrl,
    ].where((u) => u.isNotEmpty).toSet().take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      // Niente riquadro: una riga col ventaglio delle copertine, il nome e
      // il play nel colore del brano.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.br(AppRadius.lg),
          onTap: () => openReplayStory(context, period),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  height: 56,
                  child: Stack(
                    children: [
                      for (var i = covers.length - 1; i >= 0; i--)
                        Positioned(
                          left: i * 10.0,
                          top: 0,
                          // Macchie piccole, quindi poco storte, una sopra
                          // l'altra come carte.
                          child: Opacity(
                            opacity: 1 - i * 0.2,
                            child: SizedBox.square(
                              dimension: 56,
                              child: SpotThumbnail(url: covers[i], wobble: 0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Replay', style: context.texts.headlineSmall),
                      Text(
                        'Your top music, to watch and share',
                        style: context.texts.bodyMedium?.copyWith(
                          color: context.colors.accentMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.play_circle_fill_rounded,
                  size: 32,
                  color: context.colors.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Il tempo ascoltato, grande, sul colore della pagina.
class _Hero extends StatelessWidget {
  final ReplaySummary replay;
  final String? note;

  const _Hero({required this.replay, this.note});

  @override
  Widget build(BuildContext context) {
    // Il tempo ascoltato e' il numero della pagina: enorme, sul nero, senza
    // riquadro. Le altre cifre sotto, piccole, nel colore del brano.
    final colors = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              listeningTime(replay.seconds ~/ 60),
              style: context.texts.displayLarge?.copyWith(
                fontSize: wide ? 112 : 68,
                height: 0.95,
                fontWeight: FontWeight.w800,
                fontFeatures: AppTypography.tabular,
              ),
            ),
          ),
          Text(
            'listened  ·  ${replay.plays} play${replay.plays == 1 ? '' : 's'}'
            '  ·  ${replay.songs} song${replay.songs == 1 ? '' : 's'}',
            style: context.texts.titleMedium?.copyWith(
              color: colors.accentMuted,
              fontFeatures: AppTypography.tabular,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              note!,
              style: context.texts.bodySmall?.copyWith(color: colors.textFaint),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _SongRow extends ConsumerWidget {
  final int rank;
  final ReplayTrack entry;
  final List<dynamic> queue;

  const _SongRow({
    required this.rank,
    required this.entry,
    required this.queue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = entry.track;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Largo abbastanza per due cifre; dalla decima in giu' il numero
          // si stringe invece di andare a capo una cifra per riga.
          SizedBox(
            width: 34,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$rank',
                maxLines: 1,
                textAlign: TextAlign.center,
                // Il posto in classifica grande e nel colore del brano,
                // come il numero di una lista di festival.
                style: context.texts.headlineMedium?.copyWith(
                  color: context.colors.accent,
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // La stessa macchia del brano nelle liste; senza copertina,
          // l'iniziale dentro una macchia seminata dal titolo.
          SizedBox.square(
            dimension: 44,
            child: t.thumbnailUrl.isEmpty
                ? Spot(
                    seed: t.title,
                    wobble: 0.6,
                    child: _Initial(name: t.title),
                  )
                : SpotThumbnail(url: t.thumbnailUrl, wobble: 0.6),
          ),
        ],
      ),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.titleMedium,
      ),
      subtitle: Text(
        '${t.author} · ${entry.plays} play${entry.plays == 1 ? '' : 's'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodyMedium?.copyWith(
          color: context.colors.accentMuted,
        ),
      ),
      trailing: Text(
        listeningTime(entry.seconds ~/ 60),
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.textFaint,
          fontFeatures: AppTypography.tabular,
        ),
      ),
      // Dalla classifica, non da solo: finito questo, continua col
      // successivo in classifica, come ascoltando la playlist di Replay.
      onTap: () =>
          ref.read(playerProvider.notifier).playTrack(t, queue: queue.cast()),
    );
  }
}

/// Gli artisti come facce in fila, con il loro posto in classifica.
/// Gli artisti piu' ascoltati come macchie grandi quanto il loro tempo:
/// il primo e' la macchia piu' grande, gli altri via via piu' piccoli, in
/// fila sulla stessa linea di base. Si legge la classifica dalla misura
/// prima ancora che dal numero.
class _ArtistRail extends StatelessWidget {
  final List<ReplayArtist> artists;

  const _ArtistRail({required this.artists});

  @override
  Widget build(BuildContext context) {
    final shown = artists.take(10).toList();
    final top = shown.isEmpty ? 1 : math.max(1, shown.first.seconds);
    final colors = context.colors;
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter + RailBleed.of(context),
        ),
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) {
          final a = shown[i];
          final f = (a.seconds / top).clamp(0.0, 1.0);
          final size = 84 + 92 * math.sqrt(f);
          return MouseRegion(
            cursor: a.artistId == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: a.artistId == null
                  ? null
                  : () => openArtist(context, a.artistId!, a.name),
              child: SizedBox(
                width: math.max(size, 110),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox.square(
                      dimension: size,
                      child: a.artwork.isEmpty
                          ? Spot(
                              seed: a.name,
                              child: _Initial(name: a.name),
                            )
                          : SpotThumbnail(url: a.artwork),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${i + 1}  ',
                            style: TextStyle(color: colors.accent),
                          ),
                          TextSpan(text: a.name),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      listeningTime(a.seconds ~/ 60),
                      style: context.texts.bodySmall?.copyWith(
                        color: colors.accentMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// L'iniziale al posto di una copertina che manca.
class _Initial extends StatelessWidget {
  final String name;

  const _Initial({required this.name});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.1),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
