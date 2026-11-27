import 'dart:async';
import 'dart:convert';

import '../models/artist.dart';
import '../models/track.dart';
import 'spotify_api.dart';
import 'youtube_service.dart';

/// L'import di una libreria Spotify: cosa si e' scelto, cosa si e' gia'
/// trovato su YouTube Music, cosa e' gia' entrato in Crocuta.
///
/// Tutto lo stato sta in [SpotifyImportState], che si salva mentre si
/// procede: centinaia di ricerche su YouTube Music richiedono minuti, e
/// YouTube rallenta chi chiede troppo (429). Chiudendo l'app o fermandosi
/// per un errore, si riparte da dove si era arrivati — le ricerche fatte
/// restano fatte.

enum SpotifySourceKind { liked, playlist, album, artist }

/// Una cosa da importare: i piaciuti, una playlist, un disco, un artista.
class SpotifySource {
  final SpotifySourceKind kind;

  /// L'id Spotify; 'liked' per i piaciuti.
  final String id;
  final String name;

  /// Per i dischi gli interpreti, per le playlist il proprietario.
  final String subtitle;
  final String? imageUrl;
  final int count;

  /// Spotify non ne dara' i brani (playlist di altri).
  final bool restricted;

  /// Quando e' stato salvato, per i dischi: i loro brani vanno fra i
  /// piaciuti di quel giorno.
  final DateTime? addedAt;

  const SpotifySource({
    required this.kind,
    required this.id,
    required this.name,
    this.subtitle = '',
    this.imageUrl,
    this.count = 0,
    this.restricted = false,
    this.addedAt,
  });

  String get key => '${kind.name}:$id';

  bool get hasTracks =>
      kind == SpotifySourceKind.liked || kind == SpotifySourceKind.playlist;

  factory SpotifySource.liked(int count) => SpotifySource(
    kind: SpotifySourceKind.liked,
    id: 'liked',
    name: 'Liked Songs',
    count: count,
  );

  factory SpotifySource.playlist(SpotifyPlaylist p, String userId) =>
      SpotifySource(
        kind: SpotifySourceKind.playlist,
        id: p.id,
        name: p.name,
        subtitle: p.ownerName,
        imageUrl: p.imageUrl,
        count: p.total,
        restricted: !p.readableBy(userId),
      );

  factory SpotifySource.album(SpotifyAlbum a) => SpotifySource(
    kind: SpotifySourceKind.album,
    id: a.id,
    name: a.name,
    subtitle: a.artists.join(', '),
    imageUrl: a.imageUrl,
    count: a.totalTracks,
    addedAt: a.addedAt,
  );

  factory SpotifySource.artist(SpotifyArtist a) => SpotifySource(
    kind: SpotifySourceKind.artist,
    id: a.id,
    name: a.name,
    imageUrl: a.imageUrl,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'name': name,
    if (subtitle.isNotEmpty) 'sub': subtitle,
    if (imageUrl != null) 'img': imageUrl,
    'count': count,
    if (restricted) 'restricted': true,
    if (addedAt != null) 'added': addedAt!.millisecondsSinceEpoch,
  };

  factory SpotifySource.fromJson(Map<String, dynamic> j) => SpotifySource(
    kind: SpotifySourceKind.values.byName(j['kind'] as String),
    id: j['id'] as String,
    name: j['name'] as String,
    subtitle: (j['sub'] as String?) ?? '',
    imageUrl: j['img'] as String?,
    count: (j['count'] as int?) ?? 0,
    restricted: j['restricted'] == true,
    addedAt: j['added'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(j['added'] as int),
  );
}

/// Il disco trovato su YouTube Music, con i suoi brani.
typedef AlbumMatch = ({String browseId, String title, List<Track> tracks});

/// L'artista trovato, con le uscite che ha gia': seguendolo si segnano
/// come viste, come fa il tasto "Segui" (vedi FollowsController.follow).
typedef ArtistMatch = ({
  String browseId,
  String name,
  String? thumbnailUrl,
  List<String> releases,
});

/// Lo stato di un import, quello che si salva.
class SpotifyImportState {
  final List<SpotifySource> sources;

  /// I brani di Spotify, per raccolta (piaciuti e playlist), nel loro
  /// ordine. Una raccolta e' qui quando e' stata letta tutta.
  final Map<String, List<SpotifyTrack>> tracks;

  /// Le raccolte che Spotify non ha voluto dare, col motivo.
  final Map<String, String> unreadable;

  /// Per ogni brano di Spotify ([SpotifyTrack.key]) il brano di YouTube
  /// Music, o null se si e' cercato e non c'e'. Chi manca e' da cercare.
  final Map<String, Track?> songs;

  /// I brani scelti a mano dopo che la ricerca automatica non li aveva
  /// trovati: un nuovo "riprova" non li deve rimettere in discussione.
  final Set<String> manual;

  /// Dischi e artisti trovati (null: non trovati), per [SpotifySource.key].
  final Map<String, AlbumMatch?> albums;
  final Map<String, ArtistMatch?> artists;

  /// Cosa e' gia' entrato in Crocuta, per raccolta: le chiavi dei brani
  /// (o 'all' per dischi e artisti). Applicare due volte non deve
  /// raddoppiare niente, ne' rimettere un piaciuto tolto nel frattempo.
  final Map<String, Set<String>> applied;

  /// La playlist di Crocuta creata per ogni playlist di Spotify.
  final Map<String, String> playlistIds;

  final int startedAt;

  SpotifyImportState({
    required this.sources,
    Map<String, List<SpotifyTrack>>? tracks,
    Map<String, String>? unreadable,
    Map<String, Track?>? songs,
    Set<String>? manual,
    Map<String, AlbumMatch?>? albums,
    Map<String, ArtistMatch?>? artists,
    Map<String, Set<String>>? applied,
    Map<String, String>? playlistIds,
    required this.startedAt,
  }) : tracks = tracks ?? {},
       unreadable = unreadable ?? {},
       songs = songs ?? {},
       manual = manual ?? {},
       albums = albums ?? {},
       artists = artists ?? {},
       applied = applied ?? {},
       playlistIds = playlistIds ?? {};

  /// I brani da cercare, una volta sola anche se stanno in piu' raccolte,
  /// nell'ordine in cui compaiono.
  List<SpotifyTrack> get pendingSongs {
    final seen = <String>{};
    return [
      for (final s in sources)
        for (final t in tracks[s.key] ?? const <SpotifyTrack>[])
          if (!songs.containsKey(t.key) && seen.add(t.key)) t,
    ];
  }

  /// Tutti i brani distinti delle raccolte lette.
  int get totalSongs => {
    for (final s in sources)
      for (final t in tracks[s.key] ?? const <SpotifyTrack>[]) t.key,
  }.length;

  int get foundSongs => songs.values.where((t) => t != null).length;

  /// I brani cercati e non trovati, ognuno con le raccolte in cui sta.
  List<({SpotifyTrack track, List<String> sources})> get missing {
    final where = <String, List<String>>{};
    final byKey = <String, SpotifyTrack>{};
    for (final s in sources) {
      for (final t in tracks[s.key] ?? const <SpotifyTrack>[]) {
        if (!songs.containsKey(t.key) || songs[t.key] != null) continue;
        byKey.putIfAbsent(t.key, () => t);
        final list = where.putIfAbsent(t.key, () => []);
        if (!list.contains(s.name)) list.add(s.name);
      }
    }
    return [
      for (final e in byKey.entries) (track: e.value, sources: where[e.key]!),
    ];
  }

  List<SpotifySource> get missingAlbums => [
    for (final s in sources)
      if (s.kind == SpotifySourceKind.album &&
          albums.containsKey(s.key) &&
          albums[s.key] == null)
        s,
  ];

  List<SpotifySource> get missingArtists => [
    for (final s in sources)
      if (s.kind == SpotifySourceKind.artist &&
          artists.containsKey(s.key) &&
          artists[s.key] == null)
        s,
  ];

  /// Ogni raccolta letta, ogni brano cercato, ogni cosa applicata.
  bool get finished {
    for (final s in sources) {
      switch (s.kind) {
        case SpotifySourceKind.liked || SpotifySourceKind.playlist:
          if (unreadable.containsKey(s.key)) continue;
          final list = tracks[s.key];
          if (list == null) return false;
          final done = applied[s.key] ?? const {};
          for (final t in list) {
            if (!songs.containsKey(t.key)) return false;
            if (songs[t.key] != null && !done.contains(t.key)) return false;
          }
          // Una playlist vuota (o tutta non trovata) conta come fatta solo
          // dopo essere stata creata.
          if (s.kind == SpotifySourceKind.playlist &&
              !playlistIds.containsKey(s.key) &&
              list.any((t) => songs[t.key] != null)) {
            return false;
          }
        case SpotifySourceKind.album:
          if (!albums.containsKey(s.key)) return false;
          if (albums[s.key] != null && !(applied[s.key]?.isNotEmpty ?? false)) {
            return false;
          }
        case SpotifySourceKind.artist:
          if (!artists.containsKey(s.key)) return false;
          if (artists[s.key] != null &&
              !(applied[s.key]?.isNotEmpty ?? false)) {
            return false;
          }
      }
    }
    return true;
  }

  /// Rimette in coda cio' che non si era trovato, per riprovare: i brani
  /// (tranne quelli scelti a mano), i dischi, gli artisti, le raccolte
  /// che Spotify aveva rifiutato.
  void forgetMissing() {
    songs.removeWhere((k, v) => v == null && !manual.contains(k));
    albums.removeWhere((_, v) => v == null);
    artists.removeWhere((_, v) => v == null);
    for (final k in unreadable.keys) {
      tracks.remove(k);
    }
    unreadable.clear();
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'started': startedAt,
    'sources': [for (final s in sources) s.toJson()],
    'tracks': {
      for (final e in tracks.entries)
        e.key: [for (final t in e.value) t.toJson()],
    },
    'unreadable': unreadable,
    'songs': {for (final e in songs.entries) e.key: e.value?.toJson()},
    'manual': manual.toList(),
    'albums': {
      for (final e in albums.entries)
        e.key: e.value == null
            ? null
            : {
                'id': e.value!.browseId,
                'title': e.value!.title,
                'tracks': [for (final t in e.value!.tracks) t.toJson()],
              },
    },
    'artists': {
      for (final e in artists.entries)
        e.key: e.value == null
            ? null
            : {
                'id': e.value!.browseId,
                'name': e.value!.name,
                'thumb': e.value!.thumbnailUrl,
                'releases': e.value!.releases,
              },
    },
    'applied': {for (final e in applied.entries) e.key: e.value.toList()},
    'playlists': playlistIds,
  };

  String encode() => jsonEncode(toJson());

  static SpotifyImportState? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return SpotifyImportState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Uno stato illeggibile (una versione futura, un file troncato) non
      // deve bloccare la pagina: si ricomincia.
      return null;
    }
  }

  factory SpotifyImportState.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(Object? o) =>
        o is Map ? o.cast<String, dynamic>() : <String, dynamic>{};
    Track? track(Object? o) =>
        o is Map ? Track.fromJson(o.cast<String, dynamic>()) : null;
    return SpotifyImportState(
      startedAt: j['started'] as int? ?? 0,
      sources: [
        for (final s in j['sources'] as List? ?? const [])
          SpotifySource.fromJson(m(s)),
      ],
      tracks: {
        for (final e in m(j['tracks']).entries)
          e.key: [for (final t in e.value as List) SpotifyTrack.fromJson(m(t))],
      },
      unreadable: m(j['unreadable']).cast<String, String>(),
      songs: {for (final e in m(j['songs']).entries) e.key: track(e.value)},
      manual: {for (final k in j['manual'] as List? ?? const []) k as String},
      albums: {
        for (final e in m(j['albums']).entries)
          e.key: e.value == null
              ? null
              : (
                  browseId: m(e.value)['id'] as String,
                  title: m(e.value)['title'] as String? ?? '',
                  tracks: [
                    for (final t in m(e.value)['tracks'] as List? ?? const [])
                      track(t)!,
                  ],
                ),
      },
      artists: {
        for (final e in m(j['artists']).entries)
          e.key: e.value == null
              ? null
              : (
                  browseId: m(e.value)['id'] as String,
                  name: m(e.value)['name'] as String? ?? '',
                  thumbnailUrl: m(e.value)['thumb'] as String?,
                  releases: [
                    for (final r in m(e.value)['releases'] as List? ?? const [])
                      r as String,
                  ],
                ),
      },
      applied: {
        for (final e in m(j['applied']).entries)
          e.key: {for (final k in e.value as List) k as String},
      },
      playlistIds: m(j['playlists']).cast<String, String>(),
    );
  }
}

// ---------------------------------------------------------------------------
// Da Spotify a YouTube Music
// ---------------------------------------------------------------------------

/// Il titolo di Spotify senza le aggiunte da catalogo che YouTube Music
/// di solito non ha: "Song - Remastered 2011", "Song - 2015 Remaster",
/// "Song - Radio Edit", "Song - Mono". Restano "- Live", "- Remix",
/// "- Acoustic": quelle sono un'altra cosa da sentire.
String spotifyPlainTitle(String title) => title
    .replaceAll(
      RegExp(
        r'\s+-\s+(?:(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?(?:\s+version)?'
        r'|radio edit|single version|album version|mono(?:\s+version)?'
        r'|stereo(?:\s+version)?|original mix)\s*$',
        caseSensitive: false,
      ),
      '',
    )
    .replaceAll(
      RegExp(
        r'\s*[\(\[]\s*(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?(?:\s+version)?\s*[\)\]]',
        caseSensitive: false,
      ),
      '',
    )
    .trim();

/// Le ricerche da fare per un brano, in ordine: col primo interprete,
/// poi con tutti (su YouTube Music un brano a due nomi a volte e'
/// schedato sotto il secondo). Le stesse per l'import da Apple Music.
List<String> spotifySongQueries(SpotifyTrack t) {
  final title = YouTubeService.stripFeaturing(spotifyPlainTitle(t.name));
  final first = t.artists.isEmpty ? '' : t.artists.first;
  return [
    '$first $title'.trim(),
    if (t.artists.length > 1) '${t.artists.join(' ')} $title'.trim(),
  ];
}

/// Quale dei risultati di una ricerca "Songs" e' il brano di Spotify.
///
/// Il confronto e' [YouTubeService.pickCatalogSong] (titolo senza ospiti
/// ne' edizioni, primo interprete, durata entro dieci secondi), provato
/// col titolo com'e' e poi senza "Remastered" e simili.
String? pickSpotifyMatch(SpotifyTrack t, List<Track> results) {
  final candidates = [
    for (final r in results)
      (
        candidate: (id: r.id, title: r.title, artists: r.author),
        duration: r.duration,
      ),
  ];
  final titles = {t.name, spotifyPlainTitle(t.name)};
  for (final title in titles) {
    final id = YouTubeService.pickCatalogSong(
      title,
      t.artist,
      t.duration,
      candidates,
    );
    if (id != null) return id;
  }
  return null;
}

String _plain(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Il titolo di un disco senza l'edizione: "(Deluxe Edition)",
/// "[Remastered 2009]", "- Expanded Edition". Lo stesso disco su YouTube
/// Music ha spesso un'edizione diversa da quella salvata su Spotify.
String albumTitleKey(String title) => _plain(
  title
      .replaceAll(
        RegExp(
          r'\s*[\(\[][^\)\]]*\b(deluxe|edition|remaster(ed)?|expanded|anniversary|version|bonus)\b[^\)\]]*[\)\]]',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\s+-\s+.*\b(deluxe|edition|remaster(ed)?|expanded|anniversary|version)\b.*$',
          caseSensitive: false,
        ),
        '',
      ),
);

/// Quale scheda di una ricerca e' il disco di Spotify: stesso titolo
/// (prima esatto, poi senza edizione) e il primo interprete nel
/// sottotitolo ("Album • Tame Impala • 2015").
String? pickAlbumMatch(SpotifySource album, List<AlbumCard> cards) {
  final who = _plain(
    YouTubeService.primaryArtist(album.subtitle.split(',').first),
  );
  bool byArtist(AlbumCard c) => who.isEmpty || _plain(c.subtitle).contains(who);
  for (final key in [_plain(album.name), albumTitleKey(album.name)]) {
    if (key.isEmpty) continue;
    for (final c in cards) {
      if (!byArtist(c)) continue;
      if (_plain(c.title) == key || albumTitleKey(c.title) == key) {
        return c.browseId;
      }
    }
  }
  return null;
}

/// Quale scheda e' l'artista: lo stesso nome, a meno di maiuscole e
/// segni. "MARINA" e "Marina" si', "Marina and the Diamonds" no: per un
/// artista sbagliato seguito per sempre, meglio dirlo non trovato.
String? pickArtistMatch(String name, List<AlbumCard> cards) {
  final key = _plain(name);
  if (key.isEmpty) return null;
  for (final c in cards) {
    if (_plain(c.title) == key) return c.browseId;
  }
  return null;
}

/// Dove cercare. Un'interfaccia per poter provare l'import senza rete.
abstract class SpotifyCatalog {
  Future<Track?> findSong(SpotifyTrack track);
  Future<AlbumMatch?> findAlbum(SpotifySource album);
  Future<ArtistMatch?> findArtist(SpotifySource artist);
}

/// Il catalogo vero: YouTube Music.
class YouTubeSpotifyCatalog implements SpotifyCatalog {
  final YouTubeService yt;

  YouTubeSpotifyCatalog(this.yt);

  @override
  Future<Track?> findSong(SpotifyTrack track) async {
    for (final query in spotifySongQueries(track)) {
      final results = await yt.searchSongs(query);
      final id = pickSpotifyMatch(track, results);
      if (id != null) return results.firstWhere((r) => r.id == id);
    }
    return null;
  }

  @override
  Future<AlbumMatch?> findAlbum(SpotifySource album) async {
    final artist = YouTubeService.primaryArtist(
      album.subtitle.split(',').first,
    );
    final found = await yt.search('$artist ${album.name}'.trim());
    final id = pickAlbumMatch(album, [
      ...found.albums,
      // Il primo risultato, quando e' un disco, YouTube Music lo mette in
      // una scheda a parte, che la ricerca conta fra gli artisti.
      for (final a in found.artists)
        if (a.browseId.startsWith('MPRE'))
          AlbumCard(
            browseId: a.browseId,
            title: a.title,
            subtitle: artist,
            thumbnailUrl: a.thumbnailUrl,
          ),
    ]);
    if (id == null) return null;
    final page = await yt.getAlbumPage(id);
    if (page.tracks.isEmpty) return null;
    return (
      browseId: id,
      title: page.title,
      // I brani della pagina di un disco non sanno di che disco sono: senza
      // l'id il disco non comparirebbe fra gli album della libreria.
      tracks: [
        for (final t in page.tracks)
          t.albumId == null
              ? t.copyWith(albumId: id, albumName: page.title)
              : t,
      ],
    );
  }

  @override
  Future<ArtistMatch?> findArtist(SpotifySource artist) async {
    final found = await yt.search(artist.name);
    final id = pickArtistMatch(artist.name, found.artists);
    if (id == null) return null;
    final page = await yt.getArtistPage(id);
    return (
      browseId: id,
      name: page.name.isEmpty ? artist.name : page.name,
      thumbnailUrl: page.thumbnailUrl,
      releases: [
        for (final a in [...page.albums, ...page.singles]) a.browseId,
      ],
    );
  }
}

/// Dove finiscono le cose trovate: la libreria di Crocuta.
abstract class SpotifyLibrarySink {
  /// Aggiunge ai piaciuti, dal piu' recente.
  Future<void> addLiked(List<Track> newestFirst);

  /// Crea una playlist e ne restituisce l'id.
  Future<String> createPlaylist(String name, List<Track> tracks);

  /// Mette nella playlist [id] i brani [fresh] di [ordered], ognuno dopo
  /// quello che lo precede su Spotify. False se la playlist non c'e' piu'.
  Future<bool> addToPlaylist(String id, List<Track> ordered, Set<String> fresh);

  Future<void> follow(ArtistMatch artist);
}

/// I brani [fresh] di [ordered] inseriti in [current], ognuno subito dopo
/// il brano che lo precede in [ordered] e che c'e' in [current] — cosi'
/// un brano trovato al secondo tentativo torna al suo posto, e quelli
/// aggiunti, tolti o spostati a mano nel frattempo restano come sono.
List<Track> mergeIntoPlaylist(
  List<Track> current,
  List<Track> ordered,
  Set<String> fresh,
) {
  final out = [...current];
  for (var i = 0; i < ordered.length; i++) {
    final t = ordered[i];
    if (!fresh.contains(t.id) || out.any((o) => o.id == t.id)) continue;
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      final prev = out.indexWhere((o) => o.id == ordered[j].id);
      if (prev >= 0) {
        at = prev + 1;
        break;
      }
    }
    out.insert(at, t);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Il lavoro
// ---------------------------------------------------------------------------

enum SpotifyImportPhase { reading, matching, albums, artists, saving, done }

class SpotifyImportProgress {
  final SpotifyImportPhase phase;
  final int done;
  final int total;

  /// Cosa si sta facendo: "Hope — XXXTENTACION", "Reading Liked Songs".
  final String current;

  /// Quando YouTube ha chiesto di rallentare: fino a quando si aspetta.
  final DateTime? waitingUntil;

  const SpotifyImportProgress({
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.current = '',
    this.waitingUntil,
  });
}

/// YouTube Music ha detto basta (429) troppe volte di fila: si smette e si
/// riprende piu' tardi, con lo stato salvato.
class SpotifyRateLimited implements Exception {
  const SpotifyRateLimited();

  @override
  String toString() =>
      'YouTube Music is limiting searches. The import is saved: resume it '
      'in a few minutes.';
}

bool _isRateLimit(Object e) =>
    e.toString().contains('429') ||
    e.toString().toLowerCase().contains('too many requests');

/// Fa l'import, a passi che si possono interrompere e riprendere.
class SpotifyImporter {
  final SpotifyCatalog catalog;
  final SpotifyLibrarySink sink;

  /// Legge i brani di una raccolta da Spotify.
  final Future<List<SpotifyTrack>> Function(SpotifySource source) readTracks;

  /// Salva lo stato. Chiamato spesso: dopo ogni raccolta letta, ogni
  /// pochi brani cercati, ogni cosa applicata.
  final Future<void> Function(SpotifyImportState state) save;
  final Future<void> Function(Duration) sleep;

  /// Ricerche in parallelo: poche, per non farsi rallentare da YouTube.
  final int concurrency;

  /// La pausa fra una ricerca e la successiva di ogni lavoratore.
  final Duration pause;

  /// Le attese dopo un 429, una per tentativo: finite queste, ci si ferma.
  final List<Duration> backoff;

  final DateTime Function() now;

  SpotifyImporter({
    required this.catalog,
    required this.sink,
    required this.readTracks,
    required this.save,
    Future<void> Function(Duration)? sleep,
    this.concurrency = 2,
    this.pause = const Duration(milliseconds: 350),
    this.backoff = const [
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(seconds: 60),
      Duration(seconds: 120),
    ],
    DateTime Function()? now,
  }) : sleep = sleep ?? Future<void>.delayed,
       now = now ?? DateTime.now;

  /// Porta avanti [state] fin dove si puo'. Ritorna quando e' finito o
  /// quando [cancelled] dice di fermarsi; lancia [SpotifyRateLimited] se
  /// YouTube non smette di rifiutare, altri errori se Spotify non risponde.
  /// In ogni caso lo stato e' salvato.
  Future<void> run(
    SpotifyImportState state, {
    required void Function(SpotifyImportProgress) onProgress,
    bool Function()? cancelled,
  }) async {
    bool stop() => cancelled?.call() ?? false;
    try {
      await _read(state, onProgress, stop);
      if (stop()) return;
      await _matchSongs(state, onProgress, stop);
      if (stop()) return;
      await _matchAlbums(state, onProgress, stop);
      if (stop()) return;
      await _matchArtists(state, onProgress, stop);
      if (stop()) return;
      onProgress(const SpotifyImportProgress(phase: SpotifyImportPhase.saving));
      await apply(state);
      onProgress(const SpotifyImportProgress(phase: SpotifyImportPhase.done));
    } finally {
      await save(state);
    }
  }

  Future<void> _read(
    SpotifyImportState state,
    void Function(SpotifyImportProgress) onProgress,
    bool Function() stop,
  ) async {
    final todo = [
      for (final s in state.sources)
        if (s.hasTracks &&
            !state.tracks.containsKey(s.key) &&
            !state.unreadable.containsKey(s.key))
          s,
    ];
    for (var i = 0; i < todo.length; i++) {
      if (stop()) return;
      final s = todo[i];
      onProgress(
        SpotifyImportProgress(
          phase: SpotifyImportPhase.reading,
          done: i,
          total: todo.length,
          current: s.name,
        ),
      );
      try {
        state.tracks[s.key] = await readTracks(s);
      } on SpotifyApiException catch (e) {
        if (!e.forbidden) rethrow;
        // Una playlist di altri: Spotify non la da', ma il resto si fa.
        state.unreadable[s.key] =
            'Spotify only shares the songs of playlists you own or '
            'collaborate on.';
      }
      await save(state);
    }
  }

  /// Una ricerca, con le attese dopo un 429. Gli altri errori (rete) si
  /// riprovano due volte; poi il brano resta da cercare, al prossimo giro.
  Future<T?> _patiently<T>(
    Future<T> Function() call,
    void Function(DateTime until) onWait,
  ) async {
    var limited = 0;
    var failed = 0;
    while (true) {
      try {
        return await call();
      } catch (e) {
        if (_isRateLimit(e)) {
          if (limited >= backoff.length) throw const SpotifyRateLimited();
          final wait = backoff[limited++];
          onWait(now().add(wait));
          await sleep(wait);
        } else {
          if (++failed > 2) return null;
          await sleep(Duration(seconds: 2 * failed));
        }
      }
    }
  }

  Future<void> _matchSongs(
    SpotifyImportState state,
    void Function(SpotifyImportProgress) onProgress,
    bool Function() stop,
  ) async {
    final todo = state.pendingSongs;
    if (todo.isEmpty) return;
    final total = state.totalSongs;
    var next = 0;
    var unsaved = 0;
    String current = '';
    DateTime? waiting;

    void report() => onProgress(
      SpotifyImportProgress(
        phase: SpotifyImportPhase.matching,
        done: state.songs.length,
        total: total,
        current: current,
        waitingUntil: waiting,
      ),
    );

    // Il primo errore che deve fermare tutti: un lavoratore che lo vede lo
    // registra e gli altri smettono di prendere brani.
    Object? fatal;

    Future<void> worker() async {
      while (fatal == null && !stop() && next < todo.length) {
        final t = todo[next++];
        current = '${t.name} — ${t.artist}';
        report();
        bool searched = false;
        Track? found;
        try {
          found = await _patiently<Track?>(
            () async {
              final r = await catalog.findSong(t);
              searched = true;
              return r;
            },
            (until) {
              waiting = until;
              report();
            },
          );
        } catch (e) {
          fatal ??= e;
          return;
        }
        waiting = null;
        // Errore di rete ripetuto: non si registra, si riprovera'.
        if (searched) {
          state.songs[t.key] = found;
          if (++unsaved >= 10) {
            unsaved = 0;
            await save(state);
          }
        }
        report();
        await sleep(pause);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    await save(state);
    if (fatal != null) throw fatal!;
  }

  Future<void> _matchAlbums(
    SpotifyImportState state,
    void Function(SpotifyImportProgress) onProgress,
    bool Function() stop,
  ) async {
    final todo = [
      for (final s in state.sources)
        if (s.kind == SpotifySourceKind.album &&
            !state.albums.containsKey(s.key))
          s,
    ];
    for (var i = 0; i < todo.length; i++) {
      if (stop()) return;
      final s = todo[i];
      onProgress(
        SpotifyImportProgress(
          phase: SpotifyImportPhase.albums,
          done: i,
          total: todo.length,
          current: '${s.name} — ${s.subtitle}',
        ),
      );
      var searched = false;
      final found = await _patiently<AlbumMatch?>(() async {
        final r = await catalog.findAlbum(s);
        searched = true;
        return r;
      }, (_) {});
      if (searched) state.albums[s.key] = found;
      await save(state);
      await sleep(pause);
    }
  }

  Future<void> _matchArtists(
    SpotifyImportState state,
    void Function(SpotifyImportProgress) onProgress,
    bool Function() stop,
  ) async {
    final todo = [
      for (final s in state.sources)
        if (s.kind == SpotifySourceKind.artist &&
            !state.artists.containsKey(s.key))
          s,
    ];
    for (var i = 0; i < todo.length; i++) {
      if (stop()) return;
      final s = todo[i];
      onProgress(
        SpotifyImportProgress(
          phase: SpotifyImportPhase.artists,
          done: i,
          total: todo.length,
          current: s.name,
        ),
      );
      var searched = false;
      final found = await _patiently<ArtistMatch?>(() async {
        final r = await catalog.findArtist(s);
        searched = true;
        return r;
      }, (_) {});
      if (searched) state.artists[s.key] = found;
      await save(state);
      await sleep(pause);
    }
  }

  /// Mette in Crocuta cio' che e' stato trovato e non c'e' ancora entrato.
  ///
  /// I piaciuti e i brani dei dischi in un colpo solo, ordinati per data
  /// di Spotify: un disco salvato a marzo sta fra i piaciuti di marzo,
  /// non in fondo a tutti. Poi le playlist, poi gli artisti.
  Future<void> apply(SpotifyImportState state) async {
    final liked = <({DateTime at, int order, Track track})>[];
    final likedKeys = <String, Set<String>>{};
    var order = 0;
    for (final s in state.sources) {
      final done = state.applied[s.key] ?? const <String>{};
      if (s.kind == SpotifySourceKind.liked) {
        for (final t in state.tracks[s.key] ?? const <SpotifyTrack>[]) {
          final y = state.songs[t.key];
          if (y == null || done.contains(t.key)) continue;
          liked.add((
            at: t.addedAt ?? DateTime(1970),
            order: order++,
            track: y,
          ));
          likedKeys.putIfAbsent(s.key, () => {}).add(t.key);
        }
      } else if (s.kind == SpotifySourceKind.album) {
        final a = state.albums[s.key];
        if (a == null || done.isNotEmpty) continue;
        final at = s.addedAt ?? DateTime(1970);
        for (final t in a.tracks) {
          liked.add((at: at, order: order++, track: t));
        }
        likedKeys.putIfAbsent(s.key, () => {}).add('all');
      }
    }
    if (liked.isNotEmpty) {
      liked.sort((a, b) {
        final c = b.at.compareTo(a.at);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
      await sink.addLiked([for (final l in liked) l.track]);
      for (final e in likedKeys.entries) {
        state.applied.putIfAbsent(e.key, () => {}).addAll(e.value);
      }
      await save(state);
    }

    for (final s in state.sources) {
      if (s.kind != SpotifySourceKind.playlist) continue;
      final list = state.tracks[s.key];
      if (list == null) continue;
      final done = state.applied.putIfAbsent(s.key, () => {});
      // Nell'ordine di Spotify, una volta sola: una playlist puo' avere
      // lo stesso brano due volte, quelle di Crocuta no.
      final ordered = <Track>[];
      final keysOf = <String, String>{};
      for (final t in list) {
        final y = state.songs[t.key];
        if (y == null || keysOf.containsKey(y.id)) continue;
        keysOf[y.id] = t.key;
        ordered.add(y);
      }
      final fresh = {
        for (final t in list)
          if (state.songs[t.key] case final y? when !done.contains(t.key)) y.id,
      };
      if (fresh.isEmpty && state.playlistIds.containsKey(s.key)) continue;
      if (ordered.isEmpty) continue;
      final id = state.playlistIds[s.key];
      if (id == null) {
        state.playlistIds[s.key] = await sink.createPlaylist(s.name, ordered);
      } else {
        // Tolta a mano dopo l'import: non la si ricrea.
        await sink.addToPlaylist(id, ordered, fresh);
      }
      done.addAll([
        for (final t in list)
          if (state.songs[t.key] != null) t.key,
      ]);
      await save(state);
    }

    for (final s in state.sources) {
      if (s.kind != SpotifySourceKind.artist) continue;
      final a = state.artists[s.key];
      final done = state.applied[s.key] ?? const <String>{};
      if (a == null || done.isNotEmpty) continue;
      await sink.follow(a);
      state.applied.putIfAbsent(s.key, () => {}).add('all');
      await save(state);
    }
  }
}
