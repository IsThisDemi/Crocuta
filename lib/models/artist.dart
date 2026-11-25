import 'track.dart';

/// A collection of albums (or singles) shown in a carousel on an artist page.
class AlbumCard {
  final String browseId;
  final String title;
  final String subtitle;
  final String thumbnailUrl;

  const AlbumCard({
    required this.browseId,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
  });
}

/// Il "mostra tutto" di una sezione della pagina artista.
///
/// La pagina artista e' un'anteprima: cinque brani su ottantuno, dieci
/// singoli su ventotto. Il resto sta dietro una seconda richiesta, e questo
/// e' il biglietto per farla — YouTube Music non la serve col solo browseId,
/// vuole anche i suoi `params`.
class SectionLink {
  final String title;
  final String browseId;
  final String? params;

  /// Se dietro c'e' un elenco di brani invece di una griglia di copertine.
  final bool songs;

  const SectionLink({
    required this.title,
    required this.browseId,
    this.params,
    this.songs = false,
  });

  /// Uguaglianza per valore: questo e' la chiave di un provider family, e
  /// con la sola identita' una pagina artista ricaricata ne fabbricherebbe
  /// uno nuovo, rifacendo una richiesta che avevamo gia' fatto.
  @override
  bool operator ==(Object other) =>
      other is SectionLink &&
      other.browseId == browseId &&
      other.params == params &&
      other.songs == songs;

  @override
  int get hashCode => Object.hash(browseId, params, songs);
}

/// An artist page: top songs plus carousels of albums, singles and playlists.
class ArtistPage {
  final String browseId;
  final String name;
  final String? thumbnailUrl;
  final List<Track> topSongs;
  final List<AlbumCard> albums;
  final List<AlbumCard> singles;
  final List<AlbumCard> playlists;

  /// Gli artisti che YouTube Music suggerisce a chi ascolta questo.
  final List<AlbumCard> similar;

  /// "49,7 Mln ascoltatori mensili", come lo scrive YouTube Music.
  final String? monthlyListeners;

  /// Dove porta la freccia accanto al titolo di una sezione, quando c'e'.
  /// Nulla quando quella sezione e' gia' completa: album a volte lo e'.
  final SectionLink? topSongsMore;
  final SectionLink? albumsMore;
  final SectionLink? singlesMore;

  const ArtistPage({
    required this.browseId,
    required this.name,
    this.thumbnailUrl,
    this.topSongs = const [],
    this.albums = const [],
    this.singles = const [],
    this.playlists = const [],
    this.similar = const [],
    this.monthlyListeners,
    this.topSongsMore,
    this.albumsMore,
    this.singlesMore,
  });
}
