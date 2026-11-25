import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/content_width.dart';
import '../widgets/large_title.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../models/track.dart';
import '../navigation.dart';
import '../services/follows_controller.dart';
import '../providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_card.dart';
import '../widgets/section_header.dart';
import '../widgets/thumbnail.dart';
import '../widgets/top_picks.dart';
import '../widgets/sub_page.dart';
import '../models/artist.dart';
import 'favorites_screen.dart';
import 'library_screen.dart';
import 'section_screen.dart';
import '../services/library_views.dart';
import '../widgets/smart_playlist_views.dart';
import '../widgets/spot_layouts.dart';
import '../widgets/voice_sheet.dart';

/// Home tab: pick up where you left off, then recents, favourites and the
/// searches you ran before.
class HomeContent extends ConsumerWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyPlayedProvider);
    final favorites = ref.watch(favoritesProvider);
    final picks = ref.watch(topPicksProvider);
    // La scheda "riprendi" solo se nel player non c'e' gia' niente: quasi
    // sempre la sessione ripristinata ha gia' messo quel brano nel mini
    // player, e la Home lo mostrava due volte, una sopra l'altra.
    final hasTrack = ref.watch(playerProvider.select((s) => s.current != null));

    void push(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    // Le ricerche recenti sono passate nella scheda Cerca, dove le
    // riscriveresti: erano l'unica cosa in Home che non parlava di ascolto.
    final isEmpty = recent.isEmpty && favorites.isEmpty;

    void play(Track t) => ref.read(playerProvider.notifier).playTrack(t);

    // La cornice sta fuori dalla SafeArea: deve vedere l'area sicura vera
    // per mettere il titolo piccolo sotto l'orologio, e dentro la SafeArea
    // quel margine risulterebbe gia' consumato.
    return CollapsingTitleFrame(
      title: 'Home',
      child: SafeArea(
        bottom: false,
        // Colonna centrata: su una finestra larga il contenuto si stirava
        // da bordo a bordo, con meta' schermo vuoto a destra. La colonna la
        // fanno i singoli blocchi, non la lista: i caroselli cosi' corrono
        // fino al bordo della finestra.
        child: BleedListFrame(
          builder: (context, column) => ListView(
            // I semafori della finestra non li scansa piu' la shell: li'
            // sopra ci passa lo sfondo di ogni pagina, e a scansarli tocca a
            // chi disegna il contenuto.
            padding: EdgeInsets.only(
              top: topWindowInset(context),
              bottom: listBottomPadding(context, ref),
            ),
            children: [
              // Il titolo grande e, di fronte, la voce: "chiedi un brano" e'
              // il modo piu' rapido di cominciare da qui.
              column(
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
                    AppSpacing.gutter,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(child: LargeTitle('Home')),
                      _AskButton(onTap: () => showVoiceSheet(context)),
                    ],
                  ),
                ),
              ),

              if (recent.isNotEmpty && !hasTrack)
                column(_ResumeCard(track: recent.first)),

              // "Ascolta di nuovo" e' il manto: le copertine che hai
              // suonato, di misure diverse e incastrate. E' la prima cosa
              // perche' e' la piu' tua, e la sezione che da' il carattere
              // alla pagina.
              if (recent.length > 1) ...[
                column(
                  SectionHeader(
                    title: 'Listen again',
                    onTitleTap: () => push(RecentsScreen(tracks: recent)),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final items = groupRecentlyPlayed(recent).take(9);
                    return SpotCoat(
                      items: [
                        for (final item in items)
                          item.isAlbum
                              ? CoatItem(
                                  imageUrl: item.track.thumbnailUrl,
                                  title: item.track.albumName!,
                                  subtitle: item.track.author,
                                  onTap: () => openAlbum(
                                    context,
                                    item.track.albumId!,
                                    title: item.track.albumName!,
                                  ),
                                )
                              : CoatItem(
                                  imageUrl: item.track.thumbnailUrl,
                                  title: item.track.title,
                                  subtitle: item.track.author,
                                  onTap: () => play(item.track),
                                ),
                      ],
                    );
                  },
                ),
              ],

              // Le uscite nuove: una griglia di righe con la data, perche'
              // qui conta il quando — e' la sola cosa della pagina che puo'
              // essere cambiata da ieri. Se non c'e' niente di nuovo la
              // sezione non compare.
              // valueOrNull: mentre si ricarica tiene le uscite di prima.
              switch (ref.watch(latestReleasesProvider).valueOrNull) {
                null => const SizedBox.shrink(),
                final releases =>
                  releases.isEmpty
                      ? const SizedBox.shrink()
                      : column(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionHeader(
                                title: 'New from artists you follow',
                                onTitleTap: () => push(
                                  SubPage(
                                    title: 'New releases',
                                    child: AlbumCardGrid(
                                      cards: [
                                        for (final r in releases)
                                          AlbumCard(
                                            browseId: r.album.browseId,
                                            title: r.album.title,
                                            subtitle: r.year == null
                                                ? r.artistName
                                                : '${r.artistName} · ${r.year}',
                                            thumbnailUrl: r.album.thumbnailUrl,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              ReleaseGrid(releases: releases),
                            ],
                          ),
                        ),
              },

              // Le stazioni degli artisti che ascolti di piu'.
              if (picks.isNotEmpty) ...[
                column(const SectionHeader(title: 'Stations for you')),
                TopPicksRail(picks: picks),
              ],

              // Le playlist che si fanno da sole dai tuoi ascolti, come
              // grappoli delle loro copertine.
              if (ref.watch(smartPlaylistsProvider).isNotEmpty) ...[
                column(const SectionHeader(title: 'Mixes for you')),
                const SmartPlaylistRail(),
              ],

              if (favorites.isNotEmpty) ...[
                column(
                  SectionHeader(
                    title: 'Liked songs',
                    onTitleTap: () => push(const FavoritesScreen()),
                  ),
                ),
                MediaCardRail(
                  itemCount: favorites.length.clamp(0, 15),
                  itemBuilder: (_, i) => MediaCard(
                    imageUrl: favorites[i].thumbnailUrl,
                    title: favorites[i].title,
                    subtitle: favorites[i].author,
                    onTap: () => play(favorites[i]),
                  ),
                ),
              ],

              if (isEmpty)
                column(
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.huge),
                    child: EmptyState(
                      icon: Icons.music_note_rounded,
                      title: 'You have not listened to anything yet',
                      message: 'Search for a song to get started.',
                      actionLabel: 'Go to Search',
                      onAction: () => ref
                          .read(navTabProvider.notifier)
                          .select(NavTabController.search),
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

/// The wide "pick this back up" card at the top of Home.
class _ResumeCard extends ConsumerWidget {
  final Track track;

  const _ResumeCard({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      child: Material(
        color: AppColors.ink700,
        borderRadius: AppRadius.br(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref.read(playerProvider.notifier).playTrack(track),
          child: Row(
            children: [
              // La copertina non tocca piu' il bordo della scheda: una
              // macchia tagliata dal pannello perderebbe la sua forma.
              // L'altezza resta 76.
              SizedBox.square(
                dimension: 76,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: SpotThumbnail(url: track.thumbnailUrl, wobble: 0.6),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CONTINUE LISTENING', style: context.texts.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleMedium,
                    ),
                    Text(
                      track.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: 40,
                  color: context.colors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Yeat · Oct 9" per le uscite degli ultimi due mesi, "Yeat · 2024" per
/// le altre: di una novita' conta il giorno, di un disco vecchio l'anno.
@visibleForTesting
String releaseSubtitle(NewRelease r, {DateTime? now}) {
  final d = r.date;
  final today = now ?? DateTime.now();
  if (d != null && today.difference(d).inDays < 60) {
    final local = d.toLocal();
    return '${r.artistName} · ${_months[local.month - 1]} ${local.day}';
  }
  return r.year == null ? r.artistName : '${r.artistName} · ${r.year}';
}

/// Una voce di "Recently played": un brano, o un album di cui ne hai
/// ascoltati piu' d'uno.
@immutable
class RecentItem {
  /// Il brano piu' recente della voce: da' copertina e artista.
  final Track track;
  final bool isAlbum;

  const RecentItem(this.track, {this.isAlbum = false});
}

/// Gli ascolti recenti come li mostra Apple Music: per disco, non per brano.
///
/// Ascoltando un album dall'inizio la riga si riempiva di sei copertine
/// identiche — sei brani dello stesso disco — e quello che si era ascoltato
/// prima finiva fuori dallo schermo. Qui due o piu' brani dello stesso album
/// diventano una sola voce, al posto del piu' recente, che apre l'album; un
/// brano solo resta un brano, che si fa ripartire. Lo stesso brano ascoltato
/// due volte conta una.
@visibleForTesting
List<RecentItem> groupRecentlyPlayed(List<Track> recent) {
  final perAlbum = <String, int>{};
  for (final t in {for (final t in recent) t.id: t}.values) {
    final album = t.albumId;
    if (album != null && album.isNotEmpty && (t.albumName ?? '').isNotEmpty) {
      perAlbum[album] = (perAlbum[album] ?? 0) + 1;
    }
  }
  final seenTracks = <String>{};
  final seenAlbums = <String>{};
  final out = <RecentItem>[];
  for (final t in recent) {
    if (!seenTracks.add(t.id)) continue;
    final album = t.albumId;
    if (album != null && (perAlbum[album] ?? 0) > 1) {
      if (seenAlbums.add(album)) out.add(RecentItem(t, isAlbum: true));
      continue;
    }
    out.add(RecentItem(t));
  }
  return out;
}

/// "Ask for a song": la voce, accanto al titolo della Home.
class _AskButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AskButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: colors.accentMuted,
        textStyle: context.texts.titleMedium,
      ),
      icon: const Icon(Icons.mic_none_rounded, size: 20),
      label: const Text('Ask for a song'),
    );
  }
}

/// Le uscite nuove in griglia: tre colonne sul Mac, una sul telefono, al
/// massimo sei voci. Ogni voce e' una macchia piccola con titolo, artista e
/// quando e' uscita.
class ReleaseGrid extends StatelessWidget {
  final List<NewRelease> releases;

  const ReleaseGrid({super.key, required this.releases});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 900
            ? 3
            : box.maxWidth >= 560
            ? 2
            : 1;
        final shown = releases.take(cols == 1 ? 4 : cols * 2).toList();
        final w =
            (box.maxWidth -
                AppSpacing.gutter * 2 -
                AppSpacing.lg * (cols - 1)) /
            cols;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              for (final r in shown)
                SizedBox(
                  width: w,
                  child: _ReleaseRow(release: r),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  final NewRelease release;

  const _ReleaseRow({required this.release});

  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    final r = release;
    final d = r.date?.toLocal();
    final when = d != null
        ? '${_months[d.month - 1]} ${d.day}'
        : (r.year?.toString() ?? '');
    final colors = context.colors;
    return InkWell(
      borderRadius: AppRadius.br(AppRadius.md),
      onTap: () => openAlbum(context, r.album.browseId, title: r.album.title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 68,
              child: SpotThumbnail(url: r.album.thumbnailUrl, wobble: 0.8),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.album.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    r.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      color: colors.accentMuted,
                    ),
                  ),
                  if (when.isNotEmpty)
                    Text.rich(
                      TextSpan(
                        text: when,
                        children: [
                          if (r.isNew)
                            TextSpan(
                              text: '   New',
                              style: TextStyle(
                                color: colors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      style: context.texts.bodySmall?.copyWith(
                        color: colors.textFaint,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
