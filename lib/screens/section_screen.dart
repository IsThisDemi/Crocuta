import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../navigation.dart';
import '../providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/sub_page.dart';
import '../widgets/track_tile.dart';
import '../widgets/spot_layouts.dart';

/// La versione completa di una sezione della pagina artista.
///
/// La pagina artista mostra un'anteprima — cinque brani su ottantuno, dieci
/// singoli su ventotto — e il resto sta dietro una seconda richiesta. Qui
/// non scorre piu' niente di lato: una griglia, o un elenco, che si leggono
/// scorrendo in giu' come tutto il resto dell'app. Su una finestra larga e'
/// anche l'unico modo comodo, perche' un carosello orizzontale col mouse si
/// trascina a fatica.
class SectionScreen extends ConsumerWidget {
  final SectionLink link;

  const SectionScreen({super.key, required this.link});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sectionProvider(link));

    return SubPage(
      title: link.title,
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load this section',
        ),
        data: (content) => link.songs
            ? _Songs(tracks: content as List<Track>)
            : AlbumCardGrid(cards: content as List<AlbumCard>),
      ),
    );
  }
}

class _Songs extends ConsumerWidget {
  final List<Track> tracks;

  const _Songs({required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return const EmptyState(
        icon: Icons.music_off_rounded,
        title: 'Nothing here',
      );
    }
    final player = ref.watch(playerProvider);
    return ListView.builder(
      padding: EdgeInsets.only(bottom: listBottomPadding(context, ref)),
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        final isCurrent = player.current?.id == track.id;
        return TrackTile(
          track: track,
          isCurrent: isCurrent,
          isPlaying: isCurrent && player.isPlaying,
          // Tutta la sezione diventa la coda: e' una lista completa, e
          // aprirne una traccia sola sprecherebbe proprio cio' per cui si
          // e' aperta questa pagina.
          onTap: () => ref
              .read(playerProvider.notifier)
              .playTrack(track, queue: List.of(tracks)),
        );
      },
    );
  }
}

/// Una griglia di dischi che si adatta alla larghezza. La usano le sezioni
/// complete e le uscite nuove della Home.
class AlbumCardGrid extends ConsumerWidget {
  final List<AlbumCard> cards;

  const AlbumCardGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cards.isEmpty) {
      return const EmptyState(
        icon: Icons.album_outlined,
        title: 'Nothing here',
      );
    }
    // Il manto in griglia: colonne sfalsate, macchie di misure un poco
    // diverse, didascalie allineate.
    return SpotGrid(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        listBottomPadding(context, ref),
      ),
      itemCount: cards.length,
      itemAt: (i) => CoatItem(
        imageUrl: cards[i].thumbnailUrl,
        title: cards[i].title,
        subtitle: cards[i].subtitle,
        onTap: () =>
            openAlbum(context, cards[i].browseId, title: cards[i].title),
      ),
    );
  }
}
