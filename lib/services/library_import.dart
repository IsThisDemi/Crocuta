import '../models/track.dart';
import 'library_views.dart';
import 'youtube_service.dart';

/// Cosa aggiungere ai piaciuti importando una libreria da fuori, e con che
/// data. [datedExisting] sono le date da dare ai piaciuti che gia' c'erano
/// e non ne avevano una.
typedef LibraryImport = ({
  List<Track> tracks,
  List<int> addedAt,
  Map<String, int> datedExisting,
});

/// Una chiave per riconoscere lo stesso brano con id diversi: titolo senza
/// ospiti ne' descrizioni del video, e primo interprete.
///
/// Serve contro i doppioni che l'id non vede: lo stesso brano salvato una
/// volta dal videoclip e una dalla canzone ha due id YouTube diversi.
String songIdentity(Track t) {
  String plain(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  final title = YouTubeService.songTitleKey(
    YouTubeService.stripFeaturing(t.title),
    loose: true,
  );
  return '$title|${plain(YouTubeService.primaryArtist(t.author))}';
}

/// I brani importati da aggiungere, nell'ordine in cui arrivano (dal piu'
/// recente), senza quelli che ci sono gia' e senza ripetizioni.
///
/// Le date vengono prima di quella del piaciuto piu' vecchio di Crocuta:
/// ordinando per "Recently Added" i brani messi qui restano in cima, e
/// subito sotto cominciano quelli importati, ognuno un secondo piu' vecchio
/// del precedente cosi' che tengano l'ordine della libreria da cui vengono.
///
/// I piaciuti di Crocuta salvati prima che si registrasse la data non ne
/// hanno una, e in "Recently Added" stanno in fondo: senza correggerli
/// finirebbero sotto tutti gli importati. Ricevono una data fra il piu'
/// vecchio datato e il primo importato, nell'ordine in cui li si vedeva.
LibraryImport planLibraryImport({
  required List<Track> existing,
  required Map<String, int> existingAddedAt,
  required List<Track> incoming,
  required int now,
}) {
  final ids = {for (final t in existing) t.id};
  final keys = {for (final t in existing) songIdentity(t)};
  final dates = [
    for (final t in existing)
      if ((existingAddedAt[t.id] ?? 0) > 0) existingAddedAt[t.id]!,
  ];
  var next = dates.isEmpty ? now : dates.reduce((a, b) => a < b ? a : b);

  final datedExisting = <String, int>{};
  for (final t in recentlyAdded(existing, existingAddedAt)) {
    if ((existingAddedAt[t.id] ?? 0) > 0) continue;
    next -= 1000;
    datedExisting[t.id] = next;
  }

  final tracks = <Track>[];
  for (final t in incoming) {
    if (!ids.add(t.id)) continue;
    if (!keys.add(songIdentity(t))) continue;
    tracks.add(t);
  }
  final addedAt = <int>[];
  for (var i = 0; i < tracks.length; i++) {
    next -= 1000;
    addedAt.add(next);
  }
  return (tracks: tracks, addedAt: addedAt, datedExisting: datedExisting);
}
