import 'artist.dart';
import 'track.dart';

/// A music album (or single/EP) with its track list.
class Album {
  final String browseId;
  final String title;
  final String artist;

  /// L'id della pagina artista, quando YouTube Music lo collega nel byline.
  final String? artistId;

  final String? year;

  /// Che disco e': "Album", "Single", "EP". Lo scrive YouTube Music prima
  /// dell'anno, e sulla pagina prende il posto che in Apple ha il genere.
  final String? kind;

  /// "14 brani • 1 ora e 1 minuto", come lo scrive YouTube Music: conteggio
  /// e durata totale gia' formattati e tradotti.
  final String? summary;
  final String thumbnailUrl;
  final List<Track> tracks;

  /// Gli scaffali che YouTube Music mette in fondo alla pagina: "Other
  /// versions", "Releases for you". Col titolo che danno loro — sono
  /// consigli di altri artisti, non "altro di questo", e chiamarli cosi'
  /// sarebbe stato falso.
  final List<(String, List<AlbumCard>)> shelves;

  const Album({
    required this.browseId,
    required this.title,
    required this.artist,
    this.artistId,
    this.year,
    this.kind,
    this.summary,
    required this.thumbnailUrl,
    this.tracks = const [],
    this.shelves = const [],
  });
}
