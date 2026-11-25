import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../navigation.dart';
import '../providers.dart';
import '../widgets/media_card.dart';
import '../widgets/section_header.dart';
import '../widgets/detail_scaffold.dart';
import 'media_detail_page.dart';

/// An album from YouTube Music. Thin adapter over [MediaDetailPage].
class AlbumScreen extends ConsumerWidget {
  final String browseId;
  final String title;

  const AlbumScreen({super.key, required this.browseId, this.title = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumPageProvider(browseId));

    return DetailScaffold(
      body: album.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _LoadError(message: 'Could not load the album'),
        data: (a) => MediaDetailPage(
          detail: MediaDetail(
            numbered: true,
            title: a.title == 'Album' ? title : a.title,
            imageUrl: a.thumbnailUrl,
            tracks: a.tracks,
            artist: a.artist,
            artistId: a.artistId,
            meta: [a.kind, a.year],
            // La riga di YouTube quando c'e' — porta anche la durata
            // totale — altrimenti il solo conteggio.
            footnote: [
              a.summary?.replaceAll(' • ', ', ') ??
                  '${a.tracks.length} song${a.tracks.length == 1 ? '' : 's'}',
            ],
            footer: _AlbumFooter(album: a),
          ),
        ),
      ),
    );
  }
}

/// Cosa c'e' dopo i brani: altro di questo artista, poi i consigli.
class _AlbumFooter extends ConsumerWidget {
  final Album album;

  const _AlbumFooter({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (album.artistId case final id?)
          _MoreBy(artistId: id, artist: album.artist, exclude: album.browseId),
        for (final (title, cards) in album.shelves)
          _Shelf(title: title, cards: cards),
      ],
    );
  }
}

/// "More by", quello vero: dalla pagina dell'artista.
///
/// YouTube in fondo all'album mette "Releases for you", che sono quasi solo
/// altri artisti — sotto The Wall: Jethro Tull, Dire Straits, i Beatles.
/// Quello che Apple mette li' e' invece altro dello stesso artista, e lo
/// sappiamo gia' leggere dalla sua pagina. Costa una richiesta, e mentre
/// arriva lo scaffale semplicemente non c'e'.
class _MoreBy extends ConsumerWidget {
  final String artistId;
  final String artist;
  final String exclude;

  const _MoreBy({
    required this.artistId,
    required this.artist,
    required this.exclude,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(artistPageProvider(artistId)).valueOrNull;
    if (page == null) return const SizedBox.shrink();
    final cards = [
      ...page.albums,
      ...page.singles,
    ].where((c) => c.browseId != exclude).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    return _Shelf(title: 'More by $artist', cards: cards);
  }
}

class _Shelf extends StatelessWidget {
  final String title;
  final List<AlbumCard> cards;

  const _Shelf({required this.title, required this.cards});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        MediaCardRail(
          itemCount: cards.length,
          itemBuilder: (_, i) => MediaCard(
            imageUrl: cards[i].thumbnailUrl,
            title: cards[i].title,
            subtitle: cards[i].subtitle,
            onTap: () =>
                openAlbum(context, cards[i].browseId, title: cards[i].title),
          ),
        ),
      ],
    );
  }
}

/// Shared failure state for the two browse pages.
class _LoadError extends StatelessWidget {
  final String message;

  const _LoadError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
