import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/accent.dart';
import '../design/chrome.dart';
import '../design/app_theme.dart';
import '../models/artist_names.dart';
import '../models/track.dart';
import '../providers.dart';
import '../widgets/artist_links.dart';
import '../widgets/artwork_backdrop.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/empty_state.dart';
import '../widgets/large_title.dart';
import '../widgets/spot_controls.dart';
import '../widgets/thumbnail.dart';
import '../widgets/track_tile.dart';
import '../widgets/content_width.dart';

/// Everything a media detail page needs to render.
class MediaDetail {
  final String title;

  /// La riga piccola sotto l'artista, unita con " · ": "Album · 2026".
  /// In Apple li' c'e' il genere; YouTube Music non lo dice, ma dice che
  /// disco e', che serve di piu'. I nulli si saltano.
  final List<String?> meta;

  /// Il riepilogo in fondo ai brani: "21 songs, 48 minutes". Apple lo mette
  /// li', dove finisce la lista, e non in testa dove si contende lo spazio
  /// con titolo e artista.
  final List<String?> footnote;

  /// L'artista, reso cliccabile davanti al resto dei metadati. Va tenuto
  /// fuori da [meta] proprio per questo: dentro una stringa gia' unita non
  /// si potrebbe rendere toccabile la sola parte che lo nomina.
  final String? artist;

  /// L'id della sua pagina, quando si conosce; senza, si cerca per nome.
  final String? artistId;

  final String imageUrl;
  final List<Track> tracks;

  /// Extra per-row trailing widget, e.g. a remove button.
  final Widget Function(Track track, int index)? trailingBuilder;

  /// Numeri di traccia al posto delle copertine: vale per gli album.
  ///
  /// La posizione basta. Il numero che manda YouTube Music coincide sempre
  /// con lei — verificato anche su un doppio album e su un'edizione deluxe,
  /// dove ci si aspetterebbero buchi o una numerazione per disco.
  final bool numbered;

  /// Cosa c'e' in fondo alla pagina, dopo i brani.
  final Widget? footer;

  /// Una copertina disegnata, al posto dell'immagine di [imageUrl].
  final Widget? cover;

  /// Fra i due pulsanti e i brani: per la ricerca dentro la raccolta.
  final Widget? tools;

  /// Cosa mostrare quando non ci sono brani, al posto del messaggio
  /// generico — per esempio "nessun risultato" mentre si cerca.
  final Widget? empty;

  /// Scorrere a sinistra toglie il brano dalla raccolta, come "Delete"
  /// nelle liste di Apple, invece di aggiungerlo alla coda.
  final void Function(Track track)? onSwipeRemove;

  const MediaDetail({
    required this.title,
    required this.imageUrl,
    required this.tracks,
    this.meta = const [],
    this.footnote = const [],
    this.artist,
    this.artistId,
    this.trailingBuilder,
    this.numbered = false,
    this.footer,
    this.cover,
    this.tools,
    this.empty,
    this.onSwipeRemove,
  });
}

/// One page for albums, remote playlists and user playlists.
///
/// These were three separate screens whose headers differed only by a label
/// and whose track rows were byte-identical apart from the class name.
///
/// The layout follows Apple Music on iOS 27: the artwork bleeds into the
/// page and tints it rather than sitting in a box, and the primary actions
/// sit directly under the title instead of being buried in a toolbar.
class MediaDetailPage extends ConsumerWidget {
  final MediaDetail detail;

  /// Quanto rientrare dall'alto. Di norma lo spazio della barra di vetro,
  /// che galleggia sopra il contenuto; dentro `SubPage`, dove la barra sta
  /// nel flusso e il contenuto comincia gia' sotto, va passato 0.
  final double? topInset;

  const MediaDetailPage({super.key, required this.detail, this.topInset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = detail.tracks;

    // The page takes its colour from its own artwork rather than from
    // whatever is playing: on an album page the album decides, the way
    // Apple Music does.
    return AccentScope(
      artworkUrl: detail.imageUrl,
      // Materiale proprio invece di ereditarlo dal chiamante: le righe sono
      // ListTile, che senza un Material antenato lanciano. Funzionava solo
      // perche' ogni chiamante lo forniva per conto suo.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // La copertina sfocata dietro, come nel player: e' la stessa
            // pagina dello stesso disco, e qui restava su fondo nero piatto
            // mentre i pulsanti prendevano gia' il colore dell'album.
            Positioned.fill(
              child: ArtworkBackdrop(
                artUrl: detail.imageUrl,
                baseColor:
                    ref
                        .watch(backdropColorProvider(detail.imageUrl))
                        .valueOrNull ??
                    Colors.black,
                palette: ref
                    .watch(artworkPaletteProvider(detail.imageUrl))
                    .valueOrNull,
                trackId: detail.imageUrl,
              ),
            ),
            // Una colonna sola: la testa del disco e' una fascia in cima
            // alla lista e scorre via con lei, la scaletta prende tutta la
            // larghezza. Era una colonna fissa per la copertina, larga un
            // terzo della finestra per tutta l'altezza: tanto spazio per
            // un'immagine sola, e sul telefono la copertina da sola
            // riempiva lo schermo prima del primo brano.
            ContentWidth(
              maxWidth: ContentWidth.wide,
              child: CollapsingTitleFrame(
                title: detail.title,
                barOffset: DetailScaffold.backButtonOffset,
                child: ListView(
                  padding: EdgeInsets.only(
                    top: topInset ?? topBarInset(context),
                    bottom: listBottomPadding(context, ref),
                  ),
                  children: [
                    _Header(detail: detail),
                    // Fuori dal ramo dei brani: mentre si cerca, un filtro
                    // senza risultati non deve far sparire il campo in cui
                    // si sta scrivendo.
                    if (detail.tools case final tools?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.gutter,
                          AppSpacing.xs,
                          AppSpacing.gutter,
                          AppSpacing.sm,
                        ),
                        child: tools,
                      ),
                    if (tracks.isEmpty)
                      detail.empty ??
                          const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.xl),
                            child: EmptyState(
                              icon: Icons.music_off_rounded,
                              title: 'No tracks available',
                            ),
                          )
                    else ...[
                      for (var i = 0; i < tracks.length; i++)
                        _Row(
                          track: tracks[i],
                          queue: tracks,
                          number: detail.numbered ? i + 1 : null,
                          albumArtist: detail.numbered ? detail.artist : null,
                          trailing: detail.trailingBuilder?.call(tracks[i], i),
                          onSwipeRemove: detail.onSwipeRemove,
                        ),
                      _Footnote(parts: detail.footnote),
                      ?detail.footer,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La testa del disco: una fascia orizzontale in cima alla lista. A
/// sinistra la copertina a macchia con i suoi satelliti, a destra il
/// titolo grande, l'artista, i dati e i comandi. Sul telefono la stessa
/// fascia, piu' piccola: copertina e titolo affiancati, i comandi sotto
/// a tutta larghezza.
class _Header extends ConsumerWidget {
  final MediaDetail detail;

  const _Header({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = [
      for (final m in detail.meta)
        if (m != null && m.isNotEmpty) m,
    ].join(' · ');
    final tracks = detail.tracks;
    final player = ref.read(playerProvider.notifier);

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 600;
        final cover = wide ? 200.0 : (box.maxWidth * 0.34).clamp(104.0, 150.0);

        final actions = tracks.isEmpty
            ? null
            : Row(
                children: [
                  // Il play e' la macchia del colore del disco, come nel
                  // player; il casuale le sta accanto come parola.
                  SpotPlayButton(
                    playing: false,
                    size: wide ? 62 : 56,
                    onPressed: () {
                      player.setShuffle(false);
                      player.playTrack(tracks.first, queue: tracks);
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _RoundAction(
                    icon: Icons.shuffle_rounded,
                    label: 'Shuffle',
                    onTap: () {
                      player.setShuffle(true);
                      final start = tracks[Random().nextInt(tracks.length)];
                      player.playTrack(start, queue: tracks);
                    },
                  ),
                ],
              );

        final text = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // In due righe al massimo: un titolo lungo ("AM I THE DRAMA?
            // (Beat Edition)") si fa piu' piccolo invece di andare a capo una
            // terza volta e spingere giu' tutta la testata.
            LayoutBuilder(
              builder: (context, box) {
                final base = context.texts.displayLarge!.copyWith(
                  height: 1.02,
                );
                final size = fitTitleSize(
                  detail.title,
                  base,
                  maxWidth: box.maxWidth,
                  largest: wide ? 46 : 28,
                  smallest: wide ? 30 : 20,
                  lines: 2,
                  direction: Directionality.of(context),
                  scaler: MediaQuery.textScalerOf(context),
                );
                return LargeTitle(
                  detail.title,
                  maxLines: 3,
                  style: base.copyWith(fontSize: size),
                );
              },
            ),
            // L'artista nel colore del disco: la seconda cosa che si legge,
            // e porta alla sua pagina.
            if (detail.artist != null && detail.artist!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              ArtistLinks.names(
                names: ArtistNames.splitArtists(detail.artist!),
                primaryId: detail.artistId,
                style:
                    (wide
                            ? context.texts.titleLarge
                            : context.texts.titleMedium)
                        ?.copyWith(color: context.colors.accent),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  color: context.colors.textFaint,
                ),
              ),
            ],
            if (wide && actions != null) ...[
              const SizedBox(height: AppSpacing.md),
              actions,
            ],
          ],
        );

        // La copertina con i satelliti: il riquadro tiene conto del terzo
        // in piu' a destra dove cadono, cosi' non finiscono sul titolo.
        final art = Padding(
          padding: EdgeInsets.only(right: cover * 0.36),
          child: SpotCover(
            url: detail.imageUrl,
            size: cover,
            satellites: 3,
            child: detail.cover ?? Thumbnail(url: detail.imageUrl),
          ),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xs,
            AppSpacing.gutter,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: wide
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.center,
                children: [
                  art,
                  SizedBox(width: wide ? AppSpacing.md : AppSpacing.xs),
                  Expanded(child: text),
                ],
              ),
              if (!wide && actions != null) ...[
                const SizedBox(height: AppSpacing.md),
                actions,
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Un comando secondario accanto al play: icona e parola, nel colore del
/// disco spento.
class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: context.colors.textStrong,
        textStyle: context.texts.titleMedium,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      icon: Icon(icon, size: 22, color: context.colors.accent),
      label: Text(label),
    );
  }
}

/// Il riepilogo sotto l'ultimo brano.
class _Footnote extends StatelessWidget {
  final List<String?> parts;

  const _Footnote({required this.parts});

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final p in parts)
        if (p != null && p.isNotEmpty) p,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Text(
        lines.join('\n'),
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.textMuted,
          height: 1.5,
        ),
      ),
    );
  }
}

/// "Riproduci" and "Casuale", side by side under the title.

class _Row extends ConsumerWidget {
  final Track track;
  final List<Track> queue;
  final Widget? trailing;

  final int? number;
  final String? albumArtist;
  final void Function(Track track)? onSwipeRemove;

  const _Row({
    required this.track,
    required this.queue,
    this.trailing,
    this.number,
    this.albumArtist,
    this.onSwipeRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(
      playerProvider.select((s) => s.current?.id == track.id),
    );
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    return TrackTile(
      track: track,
      number: number,
      albumArtist: albumArtist,
      isCurrent: isCurrent,
      isPlaying: isCurrent && isPlaying,
      trailing: trailing,
      columns: true,
      onSwipeRemove: onSwipeRemove == null ? null : () => onSwipeRemove!(track),
      onTap: () =>
          ref.read(playerProvider.notifier).playTrack(track, queue: queue),
    );
  }
}
