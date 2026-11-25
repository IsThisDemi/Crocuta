import 'package:flutter/foundation.dart';

import '../models/artist.dart';
import '../models/track.dart';
import '../providers.dart';
import 'follows_controller.dart';
import 'library_views.dart';

/// Ordinamento e filtri delle pagine della libreria: brani piaciuti,
/// scaricati, dischi, artisti e playlist.
///
/// Tutto qui e' puro, senza widget e senza disco: le pagine passano le
/// liste e le date che hanno gia', e ricevono la lista da mostrare. Cosi'
/// si prova senza un'app intorno, e la pagina ordina una volta per
/// cambiamento (vedi [Memo]) invece che a ogni ricostruzione.

/// Le voci di "Sort By", per tutte le pagine.
///
/// Ognuna ha un verso naturale — quello che si sceglie toccandola la prima
/// volta, come le intestazioni di colonna di Musica sul Mac — e le parole
/// che lo dicono nel menu: "dalla A alla Z" si capisce, "crescente" su una
/// data no.
enum SortKey {
  added('Recently Added', 'Newest First', 'Oldest First'),
  updated('Recently Updated', 'Newest First', 'Oldest First'),
  followed('Recently Followed', 'Newest First', 'Oldest First'),
  playlist('Playlist Order', 'First to Last', 'Last to First'),
  title('Title', 'A to Z', 'Z to A'),
  name('Name', 'A to Z', 'Z to A'),
  artist('Artist', 'A to Z', 'Z to A'),
  album('Album', 'A to Z', 'Z to A'),
  plays('Most Played', 'Most First', 'Fewest First'),
  duration('Duration', 'Shortest First', 'Longest First'),
  year('Year', 'Newest First', 'Oldest First');

  final String label;
  final String natural;
  final String inverse;

  const SortKey(this.label, this.natural, this.inverse);

  /// Le voci di ogni pagina; la prima e' quella di serie.
  static const liked = [added, title, artist, album, plays, duration];
  static const downloads = [added, title, artist, album, plays, duration];
  static const ofPlaylist = [playlist, title, artist, album, plays, duration];
  static const albums = [added, title, artist, year];
  static const artists = [name, followed];
  static const playlists = [added, updated, name];
}

/// I filtri delle raccolte di brani.
enum SongFilter {
  downloaded('Downloaded Only'),
  clean('Hide Explicit');

  final String label;

  const SongFilter(this.label);
}

/// Come una pagina e' ordinata e filtrata: la voce, il verso, i filtri.
@immutable
class LibraryView {
  final SortKey sort;

  /// Il verso opposto a quello naturale di [sort].
  final bool reversed;
  final Set<SongFilter> filters;

  const LibraryView(
    this.sort, {
    this.reversed = false,
    this.filters = const {},
  });

  /// La vista di serie di una pagina: la prima voce, nel suo verso.
  factory LibraryView.initial(List<SortKey> options) =>
      LibraryView(options.first);

  /// Rilegge quello che [encodeSort] e [encodeFilters] hanno salvato.
  ///
  /// Una voce che la pagina non offre piu' — o il nome di una versione
  /// vecchia — torna a quella di serie, non a un errore. "title" senza
  /// suffisso e' anche quello che salvava l'ordinamento di prima, che cosi'
  /// sopravvive all'aggiornamento.
  factory LibraryView.decode(
    String? sort,
    Iterable<String> filters, {
    required List<SortKey> options,
    List<SongFilter> allowed = const [],
  }) {
    final parts = (sort ?? '').split(':');
    final key = options.firstWhere(
      (k) => k.name == parts.first,
      orElse: () => options.first,
    );
    final reversed =
        key.name == parts.first && parts.length > 1 && parts[1] == 'rev';
    return LibraryView(
      key,
      reversed: reversed,
      filters: {
        for (final f in allowed)
          if (filters.contains(f.name)) f,
      },
    );
  }

  String get encodeSort => reversed ? '${sort.name}:rev' : sort.name;

  Set<String> get encodeFilters => {for (final f in filters) f.name};

  /// Le parole del verso attuale: "A to Z", "Newest First".
  String get direction => reversed ? sort.inverse : sort.natural;

  /// Diversa da quella di serie: il pulsante si colora, perche' una lista
  /// filtrata o in un ordine insolito non sembri una lista a cui manca
  /// qualcosa.
  bool isCustom(List<SortKey> options) =>
      sort != options.first || reversed || filters.isNotEmpty;

  /// Toccare una voce: se e' gia' quella attiva si gira il verso, come le
  /// colonne di Musica; altrimenti si passa a lei nel suo verso naturale.
  LibraryView pick(SortKey key) => key == sort
      ? LibraryView(sort, reversed: !reversed, filters: filters)
      : LibraryView(key, filters: filters);

  LibraryView toggle(SongFilter filter) => LibraryView(
    sort,
    reversed: reversed,
    filters: filters.contains(filter)
        ? ({...filters}..remove(filter))
        : {...filters, filter},
  );

  LibraryView get withoutFilters => LibraryView(sort, reversed: reversed);

  @override
  bool operator ==(Object other) =>
      other is LibraryView &&
      other.sort == sort &&
      other.reversed == reversed &&
      setEquals(other.filters, filters);

  @override
  int get hashCode =>
      Object.hash(sort, reversed, Object.hashAllUnordered(filters));

  @override
  String toString() => 'LibraryView($encodeSort, $encodeFilters)';
}

/// Ricorda l'ultimo risultato finche' gli ingressi non cambiano.
///
/// Ordinare 842 brani a ogni ricostruzione — e la pagina dei piaciuti si
/// ricostruisce a ogni cambio di brano, per il colore — e' lavoro buttato.
/// La chiave e' un record degli ingressi: le liste dei provider si
/// confrontano per identita', e un provider ne fa una nuova solo quando
/// cambia davvero.
class Memo<T> {
  Object? _key;
  late T _value;
  bool _has = false;

  T call(Object? key, T Function() compute) {
    if (_has && key == _key) return _value;
    _value = compute();
    _key = key;
    _has = true;
    return _value;
  }
}

// --- Confronto dei testi ---

const _fold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ł': 'l',
  'đ': 'd',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
};

/// Il testo come lo ordina un elenco: senza maiuscole e senza accenti.
///
/// Dart non ha una collazione per lingua, e un confronto per codice mette
/// "Écoute" dopo la Z e "beta" dopo "Zeta". Togliere gli accenti delle
/// lingue latine basta per la libreria di chiunque scriva in alfabeto
/// latino; gli altri alfabeti restano nel loro ordine, dopo.
String foldForSort(String s) {
  final lower = s.trim().toLowerCase();
  if (lower.codeUnits.every((c) => c < 0x80)) return lower;
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_fold[ch] ?? ch);
  }
  return out.toString();
}

/// Il nome di un artista come lo ordina Musica: senza "The " davanti.
///
/// "The Weeknd" sta alla W. Solo se dopo c'e' altro: un gruppo che si
/// chiama "The" resta alla T.
String artistSortKey(String name) {
  final f = foldForSort(name);
  return f.startsWith('the ') && f.length > 4 ? f.substring(4).trimLeft() : f;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// Confronto "naturale" di due chiavi gia' ripiegate: "Track 2" prima di
/// "Track 10", come nel Finder e in Musica.
int naturalCompare(String a, String b) {
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i), cb = b.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      final si = i, sj = j;
      while (i < a.length && _isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && _isDigit(b.codeUnitAt(j))) {
        j++;
      }
      final na = a.substring(si, i).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final nb = b.substring(sj, j).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final byLen = na.length.compareTo(nb.length);
      if (byLen != 0) return byLen;
      final byDigits = na.compareTo(nb);
      if (byDigits != 0) return byDigits;
      continue;
    }
    if (ca != cb) return ca.compareTo(cb);
    i++;
    j++;
  }
  return (a.length - i).compareTo(b.length - j);
}

/// Due testi a confronto, senza maiuscole ne' accenti; a parita' decide la
/// grafia originale, cosi' l'ordine non dipende dall'ordine d'ingresso.
int compareText(String a, String b) {
  final byFold = naturalCompare(foldForSort(a), foldForSort(b));
  return byFold != 0 ? byFold : a.compareTo(b);
}

int compareArtists(String a, String b) {
  final byKey = naturalCompare(artistSortKey(a), artistSortKey(b));
  return byKey != 0 ? byKey : a.compareTo(b);
}

// --- L'ordinamento comune ---

/// Ordina in modo stabile: [primary] decide, girato se [reversed]; a
/// parita' decide [tie], sempre nello stesso verso; poi la posizione di
/// partenza.
///
/// `List.sort` di Dart non e' stabile, quindi la posizione entra nel
/// confronto. Le voci [missing] — senza disco, senza durata, senza anno —
/// vanno in fondo in tutti e due i versi: in cima, girando la lista,
/// sembrerebbero il dato piu' importante.
List<T> _sortStable<T>(
  List<T> items, {
  required int Function(T a, T b) primary,
  required bool reversed,
  int Function(T a, T b)? tie,
  bool Function(T item)? missing,
}) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  int cmp((int, T) a, (int, T) b) {
    final p = primary(a.$2, b.$2);
    if (p != 0) return reversed ? -p : p;
    final t = tie?.call(a.$2, b.$2) ?? 0;
    return t != 0 ? t : a.$1.compareTo(b.$1);
  }

  if (missing == null) {
    indexed.sort(cmp);
    return [for (final (_, t) in indexed) t];
  }
  final known = [
    for (final e in indexed)
      if (!missing(e.$2)) e,
  ]..sort(cmp);
  final unknown =
      [
        for (final e in indexed)
          if (missing(e.$2)) e,
      ]..sort((a, b) {
        final t = tie?.call(a.$2, b.$2) ?? 0;
        return t != 0 ? t : a.$1.compareTo(b.$1);
      });
  return [
    for (final (_, t) in [...known, ...unknown]) t,
  ];
}

// --- Brani ---

/// Una raccolta di brani filtrata, cercata e ordinata, come la mostra la
/// pagina.
///
/// - [query]: "Find in…", su titolo, artisti e disco, senza maiuscole.
/// - [addedAt]: le date di aggiunta per [SortKey.added]. Senza, conta la
///   posizione: la lista cresce in coda, quindi l'ultimo e' il piu' nuovo.
/// - [plays]: gli ascolti per id, per [SortKey.plays].
/// - [downloaded]: gli id scaricati, per [SongFilter.downloaded].
List<Track> sortTracks(
  List<Track> tracks,
  LibraryView view, {
  String query = '',
  Map<String, int> addedAt = const {},
  Map<String, int> plays = const {},
  Set<String> downloaded = const {},
}) {
  final q = foldForSort(query);
  final clean = view.filters.contains(SongFilter.clean);
  final onlyDownloaded = view.filters.contains(SongFilter.downloaded);
  final shown = [
    for (final t in tracks)
      if ((!clean || !t.isExplicit) &&
          (!onlyDownloaded || downloaded.contains(t.id)) &&
          (q.isEmpty ||
              foldForSort(
                '${t.title}\n${t.author}\n${t.albumName ?? ''}',
              ).contains(q)))
        t,
  ];

  int byTitle(Track a, Track b) => compareText(a.title, b.title);
  int byArtist(Track a, Track b) => compareArtists(a.author, b.author);
  int byAlbum(Track a, Track b) =>
      compareText(a.albumName ?? '', b.albumName ?? '');
  int then(Track a, Track b, List<int Function(Track, Track)> fs) {
    for (final f in fs) {
      final r = f(a, b);
      if (r != 0) return r;
    }
    return 0;
  }

  switch (view.sort) {
    case SortKey.added:
      final out = recentlyAdded(shown, addedAt);
      return view.reversed ? out.reversed.toList() : out;
    case SortKey.title:
      return _sortStable(
        shown,
        primary: byTitle,
        reversed: view.reversed,
        tie: (a, b) => byArtist(a, b),
      );
    case SortKey.artist:
      // Come Musica: dentro un artista i dischi, dentro un disco i titoli.
      return _sortStable(
        shown,
        primary: byArtist,
        reversed: view.reversed,
        tie: (a, b) => then(a, b, [byAlbum, byTitle]),
      );
    case SortKey.album:
      return _sortStable(
        shown,
        primary: byAlbum,
        reversed: view.reversed,
        tie: (a, b) => then(a, b, [byArtist, byTitle]),
        missing: (t) => (t.albumName ?? '').trim().isEmpty,
      );
    case SortKey.plays:
      // Il piu' ascoltato in cima: il verso naturale qui e' decrescente.
      return _sortStable(
        shown,
        primary: (a, b) => (plays[b.id] ?? 0).compareTo(plays[a.id] ?? 0),
        reversed: view.reversed,
        tie: byTitle,
      );
    case SortKey.duration:
      return _sortStable(
        shown,
        primary: (a, b) => a.duration!.compareTo(b.duration!),
        reversed: view.reversed,
        tie: byTitle,
        missing: (t) => t.duration == null,
      );
    case SortKey.playlist ||
        SortKey.updated ||
        SortKey.followed ||
        SortKey.name ||
        SortKey.year:
      // L'ordine in cui l'hai costruita; le altre voci non sono dei brani.
      return view.reversed ? shown.reversed.toList() : shown;
  }
}

// --- Dischi ---

/// I dischi della libreria. [albums] arriva gia' dal piu' recente, che e'
/// l'ordine di serie; [years] e' l'anno d'uscita dove si conosce.
List<AlbumCard> sortAlbums(
  List<AlbumCard> albums,
  LibraryView view, {
  Map<String, int> years = const {},
}) {
  int byTitle(AlbumCard a, AlbumCard b) => compareText(a.title, b.title);
  int byArtist(AlbumCard a, AlbumCard b) =>
      compareArtists(a.subtitle, b.subtitle);

  switch (view.sort) {
    case SortKey.title:
      return _sortStable(
        albums,
        primary: byTitle,
        reversed: view.reversed,
        tie: byArtist,
      );
    case SortKey.artist:
      return _sortStable(
        albums,
        primary: byArtist,
        reversed: view.reversed,
        tie: byTitle,
      );
    case SortKey.year:
      return _sortStable(
        albums,
        primary: (a, b) => years[b.browseId]!.compareTo(years[a.browseId]!),
        reversed: view.reversed,
        // Nello stesso anno, per artista e poi per titolo.
        tie: (a, b) {
          final r = byArtist(a, b);
          return r != 0 ? r : byTitle(a, b);
        },
        missing: (a) => years[a.browseId] == null,
      );
    case _:
      return view.reversed ? albums.reversed.toList() : albums;
  }
}

/// Se offrire "Year": solo se si conosce l'anno di almeno meta' dei dischi.
///
/// YouTube Music non lo manda con i brani, e l'app lo conosce solo per i
/// dischi di cui ha gia' cercato la data. Un "per anno" con tre dischi
/// datati su settecento sarebbe un ordine che non ordina niente, con
/// un'aria sicura.
bool yearsCoverEnough(List<AlbumCard> albums, Map<String, int> years) {
  if (albums.isEmpty) return false;
  final known = albums.where((a) => years.containsKey(a.browseId)).length;
  return known * 2 >= albums.length;
}

// --- Artisti ---

/// Gli artisti che segui. [followedAt] e' quando hai cominciato a seguirli;
/// chi e' stato seguito prima che la data si registrasse sta in fondo, dal
/// piu' nuovo, come i piaciuti senza data.
List<FollowedArtist> sortArtists(
  List<FollowedArtist> artists,
  LibraryView view, {
  Map<String, int> followedAt = const {},
}) {
  switch (view.sort) {
    case SortKey.followed:
      final indexed = [for (var i = 0; i < artists.length; i++) (i, artists[i])]
        ..sort((a, b) {
          final byDate = (followedAt[b.$2.browseId] ?? 0).compareTo(
            followedAt[a.$2.browseId] ?? 0,
          );
          // A parita' di data — tutti senza — il piu' nuovo e' l'ultimo
          // della lista, che cresce in coda.
          return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
        });
      final out = [for (final (_, a) in indexed) a];
      return view.reversed ? out.reversed.toList() : out;
    case _:
      return _sortStable(
        artists,
        primary: (a, b) => compareArtists(a.name, b.name),
        reversed: view.reversed,
      );
  }
}

// --- Playlist ---

/// Le tue playlist ordinate, ognuna con la sua posizione di partenza: le
/// playlist si indirizzano per posizione, e aprirne una dopo averle
/// riordinate deve aprire quella toccata.
///
/// [ids] sono gli id stabili per posizione e [updatedAt] l'ultima modifica
/// per id; [SortKey.added] guarda la data di creazione.
List<(int, UserPlaylist)> sortPlaylists(
  List<UserPlaylist> playlists,
  LibraryView view, {
  List<String?> ids = const [],
  Map<String, int> updatedAt = const {},
}) {
  final indexed = [
    for (var i = 0; i < playlists.length; i++) (i, playlists[i]),
  ];
  int created((int, UserPlaylist) p) =>
      p.$2.createdAt?.millisecondsSinceEpoch ?? 0;
  int updated((int, UserPlaylist) p) {
    final id = p.$1 < ids.length ? ids[p.$1] : null;
    return (id == null ? null : updatedAt[id]) ?? created(p);
  }

  List<(int, UserPlaylist)> newestFirst(int Function((int, UserPlaylist)) at) {
    final out = _sortStable(
      indexed,
      primary: (a, b) => at(b).compareTo(at(a)),
      reversed: false,
      // Senza data, l'ultima creata e' la piu' nuova: si aggiungono in coda.
      tie: (a, b) => b.$1.compareTo(a.$1),
    );
    return view.reversed ? out.reversed.toList() : out;
  }

  return switch (view.sort) {
    SortKey.updated => newestFirst(updated),
    SortKey.name => _sortStable(
      indexed,
      primary: (a, b) => compareText(a.$2.name, b.$2.name),
      reversed: view.reversed,
    ),
    _ => newestFirst(created),
  };
}
