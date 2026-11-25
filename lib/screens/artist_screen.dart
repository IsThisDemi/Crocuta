import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../widgets/detail_scaffold.dart';
import '../widgets/content_width.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../design/accent.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../navigation.dart';
import '../providers.dart';
import '../widgets/app_background.dart';
import '../widgets/liquid.dart';
import '../widgets/section_header.dart';
import '../widgets/thumbnail.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';
import '../widgets/spot_controls.dart';

class ArtistScreen extends ConsumerWidget {
  final String browseId;
  final String name;

  const ArtistScreen({super.key, required this.browseId, this.name = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(artistPageProvider(browseId));
    // Nota: letto fuori dal .when, cosi sfondo e accento sono gia' quelli
    // giusti mentre il resto della pagina si sta ancora caricando.
    final artwork = page.valueOrNull?.thumbnailUrl ?? '';

    return AccentScope(
      artworkUrl: artwork,
      child: GlassScaffold(
        // Sfondo sobrio, non la foto sfocata a tutta pagina: qui
        // l'intestazione e' gia' un'immagine grande, e ripeterla dietro al
        // contenuto toglieva stacco proprio a lei.
        background: AppBackground(artworkUrl: artwork.isEmpty ? null : artwork),
        statusBarStyle: GlassStatusBarStyle.light,
        // Nessuna barra in cima. Una barra, anche di vetro, e' una riga
        // opaca stesa sulla parte piu' alta della foto: proprio dove la
        // foto dovrebbe uscire dallo schermo. Al suo posto galleggia il
        // solo tasto indietro, e il titolo "Artista" sparisce — lo diceva
        // gia' la faccia larga mezzo schermo.
        topEdgeFade: false,
        bodyOverlays: [
          Positioned(
            left: AppSpacing.gutter,
            top:
                MediaQuery.paddingOf(context).top +
                AppSpacing.xs +
                topWindowInset(context),
            child: GlassCircleIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
        body: Material(
          type: MaterialType.transparency,
          child: StatusBarScrim(
            child: Column(
              children: [
                Expanded(
                  child: page.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Could not load the artist: $e',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    data: (artist) => _ArtistBody(
                      artist: artist,
                      fallbackName: name,
                      onAlbumTap: (browseId, title) =>
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AlbumScreen(browseId: browseId, title: title),
                            ),
                          ),
                      onPlaylistTap: (browseId, title) =>
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlaylistScreen(
                                browseId: browseId,
                                title: title,
                              ),
                            ),
                          ),
                    ),
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

class _ArtistBody extends ConsumerWidget {
  final ArtistPage artist;
  final String fallbackName;
  final void Function(String browseId, String title) onAlbumTap;
  final void Function(String browseId, String title) onPlaylistTap;

  const _ArtistBody({
    required this.artist,
    required this.fallbackName,
    required this.onAlbumTap,
    required this.onPlaylistTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 'Artist' e' il ripiego che il servizio mette quando la pagina non
    // dichiara un nome: in quel caso vale di piu' quello con cui ci siamo
    // arrivati.
    final name = artist.name == 'Artist' ? fallbackName : artist.name;

    // La lista e' larga tutta la finestra: la foto arriva ai bordi e i
    // caroselli ci scorrono fino. Il testo invece sta nella colonna
    // centrata, come prima: su una finestra larga le righe correvano da
    // bordo a bordo con meta' schermo vuoto.
    return BleedListFrame(
      builder: (context, column) => ListView(
        padding: EdgeInsets.only(bottom: listBottomPadding(context, ref)),
        children: [
          column(
            _Header(
              name: name,
              thumb: artist.thumbnailUrl,
              tracks: artist.topSongs,
              page: artist,
            ),
          ),
          column(
            _TopSongs(
              tracks: artist.topSongs,
              name: name,
              more: artist.topSongsMore,
            ),
          ),
          if (artist.albums.isNotEmpty)
            _Carousel(
              title: 'Albums',
              cards: artist.albums,
              more: artist.albumsMore,
              onTap: (c) => onAlbumTap(c.browseId, c.title),
            ),
          if (artist.singles.isNotEmpty)
            _Carousel(
              title: 'Singles and EPs',
              cards: artist.singles,
              more: artist.singlesMore,
              onTap: (c) => onAlbumTap(c.browseId, c.title),
            ),
          if (artist.playlists.isNotEmpty)
            _Carousel(
              title: 'Playlists',
              cards: artist.playlists,
              onTap: (c) => onPlaylistTap(c.browseId, c.title),
            ),
          // In fondo, dove si arriva dopo aver visto cos'ha fatto questo:
          // e' il punto in cui ha senso chiedersi chi altro somiglia.
          if (artist.similar.isNotEmpty)
            _Carousel(
              title: 'Similar artists',
              cards: artist.similar,
              circle: true,
              onTap: (c) => openArtist(context, c.browseId, c.title),
            ),
        ],
      ),
    );
  }
}

/// L'intestazione dell'artista, in Macchia.
///
/// La foto non e' piu' un rettangolo a tutta finestra che sfuma (Apple
/// Music): e' una grande macchia, come le copertine, con attorno le macchie
/// dei suoi colori. Il nome le sta accanto in grande, stretto e pesante — e'
/// il titolo della pagina — e sotto i comandi: il play e' la macchia del
/// colore dell'artista, come in ogni altra pagina.
///
/// Sul telefono la macchia sta sopra e il nome sotto, entrambi allineati a
/// sinistra.
class _Header extends ConsumerWidget {
  final String name;
  final String? thumb;

  /// Serve al pulsante "Segui": seguendo si segnano come gia' viste le
  /// uscite di oggi, e per farlo serve la pagina intera, non il solo nome.
  final ArtistPage page;
  final List<Track> tracks;

  const _Header({
    required this.name,
    required this.page,
    this.thumb,
    this.tracks = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhoto = thumb != null && thumb!.isNotEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: ContentWidth.wide),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          topBarInset(context),
          AppSpacing.gutter,
          AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 700;
            final titles = _Titles(
              name: name,
              page: page,
              tracks: tracks,
              size: wide
                  ? (box.maxWidth * 0.1).clamp(56.0, 104.0)
                  : (box.maxWidth * 0.14).clamp(40.0, 60.0),
            );
            if (!hasPhoto) return titles;
            final side = wide
                ? (box.maxWidth * 0.34).clamp(220.0, 360.0)
                : (box.maxWidth * 0.62).clamp(180.0, 300.0);
            final photo = Padding(
              // Il posto per i satelliti, che escono a destra.
              padding: EdgeInsets.only(right: side * 0.22),
              child: SpotCover(
                url: thumb!,
                size: side,
                satellites: 3,
                child: Thumbnail(
                  url: thumb!,
                  fit: BoxFit.cover,
                  hiRes: true,
                  alignment: const Alignment(0, -0.35),
                ),
              ),
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  photo,
                  const SizedBox(height: AppSpacing.lg),
                  titles,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: titles),
                const SizedBox(width: AppSpacing.lg),
                photo,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Il nome grande, gli ascoltatori nel colore dell'artista, i comandi.
class _Titles extends StatelessWidget {
  final String name;
  final ArtistPage page;
  final List<Track> tracks;
  final double size;

  const _Titles({
    required this.name,
    required this.page,
    required this.tracks,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: context.texts.displayLarge?.copyWith(
            fontSize: size,
            height: 0.95,
          ),
        ),
        if (page.monthlyListeners case final m?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              m,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.titleMedium?.copyWith(
                color: context.colors.accentMuted,
              ),
            ),
          ),
        if (tracks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _Actions(page: page, tracks: tracks),
        ],
      ],
    );
  }
}

/// Riproduci · Casuale · Segui.
///
/// Il play e' la macchia del colore dell'artista, come nel player e negli
/// album; casuale e segui sono parole con la loro icona, accanto. "Segui"
/// e' una stella, non una campanella: seguire un artista e' tenerselo
/// vicino, non chiedere di essere avvisati a ogni cosa che fa.
class _Actions extends ConsumerWidget {
  final ArtistPage page;
  final List<Track> tracks;

  const _Actions({required this.page, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider.notifier);
    final following = ref
        .watch(followsProvider)
        .any((a) => a.browseId == page.browseId);
    final colors = context.colors;

    Widget word(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
    }) => TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: active ? colors.accent : colors.textStrong,
        textStyle: context.texts.titleMedium,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      icon: Icon(icon, size: 22, color: colors.accent),
      label: Text(label),
    );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        // Sempre il triangolo: vuol dire "parti da capo con questo
        // artista", non "metti in pausa".
        SpotPlayButton(
          playing: false,
          size: 64,
          onPressed: () {
            player.setShuffle(false);
            player.playTrack(tracks.first, queue: tracks);
          },
        ),
        const SizedBox(width: AppSpacing.xs),
        word(Icons.shuffle_rounded, 'Shuffle', () {
          player.setShuffle(true);
          player.playTrack(
            tracks[Random().nextInt(tracks.length)],
            queue: tracks,
          );
        }),
        word(
          following ? Icons.star_rounded : Icons.star_border_rounded,
          following ? 'Following' : 'Follow',
          () {
            final notifier = ref.read(followsProvider.notifier);
            if (following) {
              notifier.unfollow(page.browseId);
            } else {
              notifier.follow(page);
            }
          },
          active: following,
        ),
      ],
    );
  }
}

class _TopSongs extends StatelessWidget {
  final List<Track> tracks;
  final String name;
  final SectionLink? more;

  const _TopSongs({required this.tracks, required this.name, this.more});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Top songs',
          onTitleTap: more == null ? null : () => openSection(context, more!),
        ),
        // Su una finestra larga in colonne, come Apple Music su Mac: in una
        // sola, il titolo stava a sinistra e le riproduzioni a mille pixel
        // di distanza, con il vuoto in mezzo. Le colonne si riempiono
        // dall'alto in basso, cosi' l'ordine si legge come in una lista.
        LayoutBuilder(
          builder: (context, box) {
            final columns = topSongColumns(box.maxWidth, tracks.length);
            if (columns == 1) {
              return Column(
                children: [
                  for (final track in tracks)
                    _SongRow(track: track, name: name, section: tracks),
                ],
              );
            }
            final rows = (tracks.length / columns).ceil();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++)
                  Expanded(
                    child: Column(
                      children: [
                        for (
                          var i = c * rows;
                          i < min((c + 1) * rows, tracks.length);
                          i++
                        )
                          _SongRow(
                            track: tracks[i],
                            name: name,
                            section: tracks,
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SongRow extends ConsumerWidget {
  final Track track;
  final String name;

  /// I brani della sezione: toccarne uno li mette in coda tutti, da li'.
  /// Prima la coda era il brano solo, e subito dopo partiva la radio.
  final List<Track> section;

  const _SongRow({
    required this.track,
    required this.name,
    required this.section,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final isCurrent = player.current?.id == track.id;
    return TrackTile(
      track: track,
      isCurrent: isCurrent,
      isPlaying: isCurrent && player.isPlaying,
      onTap: () =>
          ref.read(playerProvider.notifier).playTrack(track, queue: section),
      onArtistTap: null,
      // Niente icona in coda: copriva le riproduzioni, e diceva una cosa
      // che la riga dice gia' — il brano in corso ha il titolo in accento e
      // le barrette animate sulla copertina.
    );
  }
}

class _Carousel extends StatelessWidget {
  final String title;
  final List<AlbumCard> cards;
  final void Function(AlbumCard card) onTap;

  /// La sezione completa, quando YouTube Music ne dichiara una. Non sempre:
  /// certi artisti hanno gia' tutti gli album nel carosello, e li' una
  /// freccia porterebbe a una copia della stessa fila.
  final SectionLink? more;

  /// Una fila di artisti. Prima erano cerchi contro i quadrati dei dischi;
  /// ora tutto e' macchia, e a distinguerli restano i nomi centrati sotto
  /// la foto, come nelle schede d'artista di `MediaCard`.
  final bool circle;

  const _Carousel({
    required this.title,
    required this.cards,
    required this.onTap,
    this.more,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Il titolo nella colonna, il carosello no: parte allineato al
        // titolo ma corre fino al bordo della finestra.
        ContentWidth(
          maxWidth: ContentWidth.wide,
          child: SizedBox(
            width: double.infinity,
            child: SectionHeader(
              title: title,
              onTitleTap: more == null
                  ? null
                  : () => openSection(context, more!),
            ),
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            // Allineato al titolo della sezione, e fino al bordo della
            // finestra quando la pagina e' larga.
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter + RailBleed.of(context),
            ),
            itemCount: cards.length,
            itemBuilder: (context, i) {
              final card = cards[i];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => onTap(card),
                  child: SizedBox(
                    width: 130,
                    child: Column(
                      crossAxisAlignment: circle
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        // Dischi e artisti simili sono macchie, senza la
                        // lastra di vetro attorno: un riquadro arrotondato
                        // dietro una macchia ne disegnerebbe gli angoli.
                        AspectRatio(
                          aspectRatio: 1,
                          child: SpotThumbnail(url: card.thumbnailUrl),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          card.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          card.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// In quante colonne mettere i brani piu' ascoltati, data la larghezza.
///
/// Una colonna sotto i 760 px (telefono, finestra stretta); due o tre sopra,
/// ma almeno due brani per colonna: i cinque brani tipici vanno su due
/// colonne da tre e due, non su tre con l'ultima da un brano solo.
@visibleForTesting
int topSongColumns(double width, int count) {
  final byWidth = width >= 1040 ? 3 : (width >= 760 ? 2 : 1);
  final byCount = max(1, count ~/ 2);
  return min(byWidth, byCount);
}
