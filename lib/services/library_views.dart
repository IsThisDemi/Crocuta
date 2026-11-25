import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artist.dart';
import '../models/artist_names.dart';
import '../models/track.dart';
import '../providers.dart';
import 'discovery_controller.dart';
import 'smart_playlists.dart';

/// I preferiti dal piu' recente, come "Recently Added" di Apple.
///
/// La data e' quella che la sincronizzazione gia' registra per ogni
/// preferito. Quelli salvati prima che esistesse hanno data zero: restano
/// in fondo, nell'ordine in cui stavano — che e' comunque quello in cui
/// sono stati aggiunti, perche' la lista cresce in coda.
List<Track> recentlyAdded(List<Track> favorites, Map<String, int> addedAt) {
  final indexed = [
    for (var i = 0; i < favorites.length; i++) (i, favorites[i]),
  ];
  indexed.sort((a, b) {
    final byDate = (addedAt[b.$2.id] ?? 0).compareTo(addedAt[a.$2.id] ?? 0);
    return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
  });
  return [for (final (_, t) in indexed) t];
}

/// I dischi dei preferiti, come la voce "Albums" di Apple: aggiungendo un
/// brano, il suo disco entra in libreria.
///
/// Solo i brani che sanno di che disco sono: senza l'id la scheda non
/// saprebbe cosa aprire. Un disco compare una volta, anche con piu' brani
/// salvati, e nell'ordine in cui e' entrato il primo.
List<AlbumCard> albumsOf(List<Track> tracks) {
  final seen = <String>{};
  return [
    for (final t in tracks)
      if (t.albumId case final id? when seen.add(id))
        AlbumCard(
          browseId: id,
          title: t.albumName ?? t.title,
          subtitle: ArtistNames.splitArtists(t.author).firstOrNull ?? t.author,
          thumbnailUrl: t.thumbnailUrl,
        ),
  ];
}

final recentlyAddedProvider = Provider<List<Track>>(
  (ref) => recentlyAdded(
    ref.watch(favoritesProvider),
    ref.read(storageServiceProvider).marks('fav'),
  ),
);

final libraryAlbumsProvider = Provider<List<AlbumCard>>(
  (ref) => albumsOf(ref.watch(recentlyAddedProvider)),
);

/// Come ordinare una raccolta di brani, le voci di "Sort By" in Apple.
///
/// La prima voce dipende dalla raccolta: i piaciuti hanno una data per
/// ogni brano e partono dal piu' recente, una playlist ha l'ordine in cui
/// l'hai costruita.
enum SongSort {
  added('Recently Added'),
  playlist('Playlist Order'),
  title('Title'),
  artist('Artist'),
  album('Album');

  final String label;

  const SongSort(this.label);

  /// Le voci per i piaciuti e per una playlist.
  static const liked = [added, title, artist, album];
  static const ofPlaylist = [playlist, title, artist, album];

  /// Una voce salvata, se e' fra quelle di [options]; altrimenti la prima.
  static SongSort byName(String? name, List<SongSort> options) =>
      options.firstWhere((s) => s.name == name, orElse: () => options.first);
}

/// Una raccolta ordinata e filtrata per la ricerca nella pagina.
///
/// Il filtro guarda titolo, artisti e disco, senza maiuscole: e' "Find in
/// Playlist" di Apple, che cerca in tutto quello che la riga mostra.
/// [addedAt] serve solo a [SongSort.added].
List<Track> sortSongs(
  List<Track> tracks, {
  required SongSort sort,
  String query = '',
  Map<String, int> addedAt = const {},
}) {
  final q = query.trim().toLowerCase();
  final matching = q.isEmpty
      ? tracks
      : [
          for (final t in tracks)
            if ('${t.title}\n${t.author}\n${t.albumName ?? ''}'
                .toLowerCase()
                .contains(q))
              t,
        ];

  switch (sort) {
    case SongSort.added:
      return recentlyAdded(matching, addedAt);
    case SongSort.playlist:
      return matching;
    case SongSort.title || SongSort.artist || SongSort.album:
      break;
  }

  String key(Track t) => switch (sort) {
    SongSort.artist => t.author,
    SongSort.album => t.albumName ?? '',
    _ => t.title,
  }.trim().toLowerCase();

  // A parita' di artista o disco, il titolo: altrimenti i brani dello
  // stesso disco uscirebbero in un ordine qualunque.
  final sorted = [...matching]
    ..sort((a, b) {
      final byKey = key(a).compareTo(key(b));
      return byKey != 0
          ? byKey
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  // Senza disco in fondo, non in cima: una riga vuota come chiave li
  // metterebbe prima della A.
  if (sort == SongSort.album) {
    return [
      ...sorted.where((t) => (t.albumName ?? '').isNotEmpty),
      ...sorted.where((t) => (t.albumName ?? '').isEmpty),
    ];
  }
  return sorted;
}

/// "21 songs, 52 minutes", come in fondo a una playlist di Apple.
///
/// I minuti solo se si conosce la durata di tutti: una somma parziale
/// direbbe un numero sbagliato con aria sicura.
String songsSummary(List<Track> tracks) {
  final n = tracks.length;
  final songs = '$n song${n == 1 ? '' : 's'}';
  if (n == 0 || tracks.any((t) => t.duration == null)) return songs;
  final total = tracks.fold(Duration.zero, (sum, t) => sum + t.duration!);
  final h = total.inHours;
  final m = total.inMinutes.remainder(60);
  final time = h == 0
      ? '$m minute${m == 1 ? '' : 's'}'
      : '$h hour${h == 1 ? '' : 's'}, $m minute${m == 1 ? '' : 's'}';
  return '$songs, $time';
}

/// Le playlist intelligenti, rifatte a ogni ascolto e a ogni cuore. Quelle
/// con meno di tre brani non si mostrano: una playlist da uno non invoglia.
final smartPlaylistsProvider = Provider<List<SmartPlaylist>>((ref) {
  final stats = ref.watch(statsProvider);
  final favorites = ref.watch(favoritesProvider);
  final storage = ref.read(storageServiceProvider);
  final now = DateTime.now();
  final log = storage.playLog;
  final tracks = {...storage.statTracks, for (final t in favorites) t.id: t};
  final addedAt = storage.marks('fav');
  final lastPlayed = {
    for (final e in stats.entries)
      if (e.value.lastPlayed case final d?) e.key: d,
  };
  return [
    // Prima la scoperta: e' la sola cosa qui dentro che non conosci gia'.
    ...ref.watch(discoveryProvider),
    for (final (kind, list) in [
      (SmartKind.onRepeat, onRepeat(log, tracks, now: now)),
      (SmartKind.recentlyLiked, recentlyLiked(favorites, addedAt, now: now)),
      (SmartKind.lateNight, lateNight(log, tracks)),
      (
        SmartKind.forgotten,
        forgotten(favorites, lastPlayed, addedAt, now: now),
      ),
    ])
      if (list.length >= 3) SmartPlaylist(kind, list),
  ];
});
