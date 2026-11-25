import 'artist.dart';
import 'track.dart';

/// Cosa mettere davanti a chi apre la ricerca senza aver ancora scritto.
///
/// Sono le tre cose che ogni app musicale mette al posto di una pagina
/// vuota: cosa va adesso, le classifiche e le uscite. Arrivano da due
/// richieste diverse a YouTube Music, ma per chi guarda sono una cosa sola.
class ExplorePage {
  /// I brani del momento, riproducibili subito.
  final List<Track> trending;

  /// Le classifiche del proprio paese, come playlist da aprire.
  final List<AlbumCard> charts;

  /// Le classifiche mondiali.
  final List<AlbumCard> globalCharts;

  /// Album e singoli appena usciti.
  final List<AlbumCard> newReleases;

  const ExplorePage({
    this.trending = const [],
    this.charts = const [],
    this.globalCharts = const [],
    this.newReleases = const [],
  });

  bool get isEmpty =>
      trending.isEmpty &&
      charts.isEmpty &&
      globalCharts.isEmpty &&
      newReleases.isEmpty;
}

/// Una categoria da sfogliare: "Chill", "Hip-Hop", "Workout".
///
/// Il colore e' quello che le da' YouTube Music: e' cio' che fa delle
/// categorie una griglia che si riconosce a colpo d'occhio, come le
/// "Browse Categories" della ricerca di Apple.
class BrowseCategory {
  final String title;
  final int color;

  /// Cosa passare alla richiesta per aprirla.
  final String params;

  const BrowseCategory({
    required this.title,
    required this.color,
    required this.params,
  });
}

/// Un gruppo di categorie: "Moods & moments", "Genres".
class CategoryGroup {
  final String title;
  final List<BrowseCategory> items;

  const CategoryGroup({required this.title, required this.items});
}
