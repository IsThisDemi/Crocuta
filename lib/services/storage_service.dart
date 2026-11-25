import 'package:hive_flutter/hive_flutter.dart';

import '../models/track.dart';
import 'listen_cap.dart';

/// Persists favorites and the last queue to disk via Hive.
class StorageService {
  static const _favoritesBoxName = 'favorites';
  static const _stateBoxName = 'state';
  static const _durationsBoxName = 'durations';
  static const _recentBoxName = 'recent';
  static const _historyBoxName = 'history';
  static const _statsBoxName = 'stats';
  static const _playlistsBoxName = 'playlists';
  static const _audioIdsBoxName = 'audio_ids';
  static const _songVersionsBoxName = 'song_versions';
  static const _playLogBoxName = 'play_log';
  static const _statTracksBoxName = 'stat_tracks';
  static const _loudnessBoxName = 'loudness';
  static const _beatsBoxName = 'beats';
  static const _lyricsBoxName = 'lyrics';

  late final Box _favoritesBox;
  late final Box _stateBox;
  late final Box _durationsBox;
  late final Box _recentBox;
  late final Box _historyBox;
  late final Box _statsBox;
  late final Box _playlistsBox;
  late final Box _audioIdsBox;
  late final Box _songVersionsBox;
  late final Box _playLogBox;
  late final Box _statTracksBox;
  late final Box _loudnessBox;
  late final Box _beatsBox;
  late final Box _lyricsBox;

  /// [path] opens the boxes in a specific directory instead of the app's
  /// support directory. Only tests pass it: `Hive.initFlutter` goes through
  /// path_provider, which needs a live platform channel.
  Future<void> init({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }
    _favoritesBox = await Hive.openBox(_favoritesBoxName);
    _stateBox = await Hive.openBox(_stateBoxName);
    _durationsBox = await Hive.openBox(_durationsBoxName);
    _recentBox = await Hive.openBox(_recentBoxName);
    _historyBox = await Hive.openBox(_historyBoxName);
    _statsBox = await Hive.openBox(_statsBoxName);
    _playlistsBox = await Hive.openBox(_playlistsBoxName);
    _audioIdsBox = await Hive.openBox(_audioIdsBoxName);
    _songVersionsBox = await Hive.openBox(_songVersionsBoxName);
    _playLogBox = await Hive.openBox(_playLogBoxName);
    _statTracksBox = await Hive.openBox(_statTracksBoxName);
    _loudnessBox = await Hive.openBox(_loudnessBoxName);
    _beatsBox = await Hive.openBox(_beatsBoxName);
    _lyricsBox = await Hive.openBox(_lyricsBoxName);
    await _prepareForSync();
    await _capListens();
  }

  /// Da' un id e una data alle voci salvate prima che esistessero.
  ///
  /// Senza, la prima sincronizzazione vedrebbe una libreria intera senza
  /// data e non saprebbe dire chi e' piu' recente fra due dispositivi. Si
  /// usa l'istante in cui il file e' stato scritto la prima volta, non
  /// "adesso": due dispositivi che migrano in momenti diversi si
  /// attribuirebbero altrimenti la versione piu' nuova a vicenda.
  Future<void> _prepareForSync() async {
    if (_stateBox.get('sync_ready') == true) return;

    // Le playlist erano indirizzate per posizione: un id stabile serve
    // perche' due dispositivi possono riordinarle.
    final pls = playlists;
    var touched = false;
    for (final pl in pls) {
      if (pl['id'] != null) continue;
      final created = pl['createdAt'] as int? ?? 0;
      final name = (pl['name'] as String?) ?? '';
      pl['id'] =
          'pl_${created}_${name.hashCode.toUnsigned(16).toRadixString(16)}';
      touched = true;
    }
    if (touched) await savePlaylists(pls);

    final plMarks = marks('pl');
    for (final pl in pls) {
      final id = pl['id'] as String;
      plMarks.putIfAbsent(id, () => pl['createdAt'] as int? ?? 0);
    }
    await setMarks('pl', plMarks);

    // I preferiti non hanno mai avuto una data: si mette zero, cosi' una
    // voce datata su un altro dispositivo vince, che e' il comportamento
    // giusto — quella e' l'unica delle due che sa quando e' nata.
    final favMarks = marks('fav');
    for (final t in favorites) {
      favMarks.putIfAbsent(t.id, () => 0);
    }
    await setMarks('fav', favMarks);

    final recMarks = marks('recent');
    for (final t in recentlyPlayed) {
      recMarks.putIfAbsent(t.id, () => 0);
    }
    await setMarks('recent', recMarks);

    await _stateBox.put('sync_ready', true);
  }

  // --- Sostituzioni in blocco, usate dalla sincronizzazione ---
  //
  // Scrivono senza toccare marche e lapidi: quelle le imposta la fusione a
  // parte, e passare da `addFavorite` qui rimetterebbe la data di adesso su
  // ogni voce, cancellando proprio l'informazione che serve a decidere chi
  // ha ragione fra due dispositivi.

  Future<void> replaceFavorites(List<Track> tracks) =>
      _favoritesBox.put('tracks', tracks.map((t) => t.toJson()).toList());

  Future<void> replaceRecentlyPlayed(List<Track> tracks) =>
      _recentBox.put('tracks', tracks.map((t) => t.toJson()).toList());

  Future<void> replaceAllPlayStats(Map<String, dynamic> stats) =>
      _statsBox.put('plays', stats);

  // --- Metadati per la sincronizzazione ---
  //
  // Stanno a parte e non dentro i brani: quando hai aggiunto un preferito e'
  // un dato della tua libreria, non del brano, e infilarlo in `Track` lo
  // farebbe viaggiare anche dove non serve.
  //
  // Le cancellazioni si registrano invece di sparire: senza, il dispositivo
  // rimasto indietro rimanderebbe su cio' che hai tolto sull'altro, e il
  // preferito eliminato tornerebbe da solo. E' la parte che la gente
  // dimentica quando scrive una sincronizzazione, ed e' quella che si nota.

  static const _marks = 'sync_marks';
  static const _graves = 'sync_graves';

  Map<String, int> _bucket(String key, String kind) {
    final raw = _stateBox.get(key, defaultValue: <dynamic, dynamic>{}) as Map;
    final all = Map<String, dynamic>.from(raw);
    return Map<String, int>.from(
      Map<String, dynamic>.from((all[kind] as Map?) ?? {}),
    );
  }

  Future<void> _putBucket(String key, String kind, Map<String, int> v) async {
    final raw = _stateBox.get(key, defaultValue: <dynamic, dynamic>{}) as Map;
    final all = Map<String, dynamic>.from(raw);
    all[kind] = v;
    await _stateBox.put(key, all);
  }

  /// Quando ogni voce e' stata aggiunta o modificata su questo dispositivo.
  Map<String, int> marks(String kind) => _bucket(_marks, kind);

  /// Quando ogni voce e' stata cancellata.
  Map<String, int> graves(String kind) => _bucket(_graves, kind);

  Future<void> mark(String kind, String id, [int? at]) async {
    final m = marks(kind)..[id] = at ?? DateTime.now().millisecondsSinceEpoch;
    final g = graves(kind)..remove(id);
    await _putBucket(_marks, kind, m);
    await _putBucket(_graves, kind, g);
  }

  Future<void> bury(String kind, String id, [int? at]) async {
    final g = graves(kind)..[id] = at ?? DateTime.now().millisecondsSinceEpoch;
    final m = marks(kind)..remove(id);
    await _putBucket(_graves, kind, g);
    await _putBucket(_marks, kind, m);
  }

  Future<void> setMarks(String kind, Map<String, int> v) =>
      _putBucket(_marks, kind, v);

  Future<void> setGraves(String kind, Map<String, int> v) =>
      _putBucket(_graves, kind, v);

  /// Quando la sincronizzazione e' riuscita l'ultima volta.
  DateTime? get lastSync {
    final ms = _stateBox.get('last_sync') as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastSync(DateTime when) =>
      _stateBox.put('last_sync', when.millisecondsSinceEpoch);

  /// Indirizzo e segreto della sincronizzazione, scelti nelle
  /// Impostazioni. `null` se non sono mai stati scritti: vuoti invece se
  /// la sincronizzazione e' stata spenta apposta.
  String? get syncUrl => _stateBox.get('sync_url') as String?;
  String? get syncSecret => _stateBox.get('sync_secret') as String?;

  Future<void> setSyncConfig(String url, String secret) async {
    await _stateBox.put('sync_url', url);
    await _stateBox.put('sync_secret', secret);
  }

  /// Aggiorna le copie salvate dei brani appena rivisti dalla rete.
  ///
  /// Preferiti, playlist e recenti conservano una copia scattata il giorno
  /// in cui li hai salvati. Tenere solo l'id renderebbe la libreria
  /// dipendente dalla rete — cinque preferiti, cinque richieste per
  /// aprirla, e niente senza connessione — quindi la copia resta, ma
  /// smette di essere la verita': ogni volta che quel brano ripassa da una
  /// ricerca, da un album o dalla radio, la copia si riallinea. Nessuna
  /// richiesta in piu': sono dati che stavamo gia' scaricando.
  ///
  /// Restituisce true se qualcosa e' cambiato, cosi' chi chiama ricarica
  /// solo quando serve.
  Future<bool> refreshCachedTracks(List<Track> fresh) async {
    if (fresh.isEmpty) return false;
    final byId = {for (final t in fresh) t.id: t};
    var changed = false;

    List<Track> apply(List<Track> stored) => [
      for (final t in stored)
        if (byId[t.id] case final f?) t.refreshedFrom(f) else t,
    ];

    bool differs(List<Track> a, List<Track> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i].title != b[i].title ||
            a[i].author != b[i].author ||
            a[i].thumbnailUrl != b[i].thumbnailUrl ||
            a[i].albumId != b[i].albumId ||
            a[i].plays != b[i].plays ||
            a[i].duration != b[i].duration) {
          return true;
        }
      }
      return false;
    }

    final favs = favorites;
    final newFavs = apply(favs);
    if (differs(favs, newFavs)) {
      await _favoritesBox.put(
        'tracks',
        newFavs.map((t) => t.toJson()).toList(),
      );
      changed = true;
    }

    final rec = recentlyPlayed;
    final newRec = apply(rec);
    if (differs(rec, newRec)) {
      await _recentBox.put('tracks', newRec.map((t) => t.toJson()).toList());
      changed = true;
    }

    final pls = playlists;
    var plsChanged = false;
    for (final pl in pls) {
      final stored = ((pl['tracks'] as List?) ?? [])
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final updated = apply(stored);
      if (differs(stored, updated)) {
        pl['tracks'] = updated.map((t) => t.toJson()).toList();
        plsChanged = true;
      }
    }
    if (plsChanged) {
      await savePlaylists(pls);
      changed = true;
    }

    return changed;
  }

  /// Se mandare avanti il brano successivo scaricandolo.
  ///
  /// Acceso di norma: costa un brano alla volta e fa partire il successivo
  /// all'istante. Spento, si scarica solo cio' che scegli tu.
  bool get autoPreload => _stateBox.get('auto_preload') as bool? ?? true;

  Future<void> setAutoPreload(bool value) =>
      _stateBox.put('auto_preload', value);

  // --- Artisti seguiti ---
  //
  // Si tiene la scheda, non solo l'id: l'elenco deve mostrare nome e foto
  // anche prima che la pagina dell'artista venga riscaricata.
  //
  // Le uscite gia' viste si registrano per artista: "nuovo" significa nuovo
  // *per te*, non pubblicato di recente — e' l'unico modo onesto di dirlo,
  // visto che YouTube Music da' l'anno e non la data.

  List<Map<String, dynamic>> get followed {
    final raw =
        _stateBox.get('followed', defaultValue: <dynamic>[]) as List<dynamic>;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> saveFollowed(List<Map<String, dynamic>> list) =>
      _stateBox.put('followed', list);

  bool isFollowing(String browseId) =>
      followed.any((a) => a['browseId'] == browseId);

  Future<void> follow({
    required String browseId,
    required String name,
    String? thumbnailUrl,
  }) async {
    if (isFollowing(browseId)) return;
    final list = followed
      ..add({'browseId': browseId, 'name': name, 'thumbnailUrl': thumbnailUrl});
    await saveFollowed(list);
    await mark('artist', browseId);
  }

  Future<void> unfollow(String browseId) async {
    await saveFollowed(
      followed.where((a) => a['browseId'] != browseId).toList(),
    );
    await bury('artist', browseId);
    final seen = Map<String, dynamic>.from(
      _stateBox.get('seen_releases', defaultValue: <dynamic, dynamic>{}) as Map,
    )..remove(browseId);
    await _stateBox.put('seen_releases', seen);
  }

  /// Le date d'uscita gia' trovate, per album o singolo: non cambiano, e
  /// trovarle costa due richieste ciascuna.
  DateTime? releaseDate(String browseId) {
    final all = _stateBox.get('release_dates') as Map?;
    final ms = all?[browseId] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setReleaseDates(Map<String, DateTime> dates) async {
    if (dates.isEmpty) return;
    final all = Map<String, dynamic>.from(
      _stateBox.get('release_dates', defaultValue: <dynamic, dynamic>{}) as Map,
    );
    for (final e in dates.entries) {
      all[e.key] = e.value.millisecondsSinceEpoch;
    }
    await _stateBox.put('release_dates', all);
  }

  /// Le uscite gia' viste di un artista.
  Set<String> seenReleases(String browseId) {
    final all =
        _stateBox.get('seen_releases', defaultValue: <dynamic, dynamic>{})
            as Map;
    final mine = (all[browseId] as List?) ?? const [];
    return mine.map((e) => e.toString()).toSet();
  }

  Future<void> setSeenReleases(String browseId, Set<String> ids) async {
    final all = Map<String, dynamic>.from(
      _stateBox.get('seen_releases', defaultValue: <dynamic, dynamic>{}) as Map,
    );
    all[browseId] = ids.toList();
    await _stateBox.put('seen_releases', all);
  }

  /// Quando si e' guardato l'ultima volta se c'erano uscite nuove.
  DateTime? get lastReleaseCheck {
    final ms = _stateBox.get('last_release_check') as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastReleaseCheck(DateTime when) =>
      _stateBox.put('last_release_check', when.millisecondsSinceEpoch);

  // --- Download scelti ---
  //
  // Si salva anche la scheda del brano, non solo l'id: un brano scaricato
  // deve comparire nell'elenco e avere titolo e copertina anche senza rete,
  // che e' il caso in cui serve. I file audio stanno altrove, in
  // `downloads/`, e chi comanda e' il disco: l'elenco qui e' l'etichetta.
  //
  // Non si sincronizzano fra dispositivi: un elenco di download su un
  // dispositivo che non ha i file direbbe una cosa falsa.

  List<Track> get downloads {
    final raw =
        _stateBox.get('downloads', defaultValue: <dynamic>[]) as List<dynamic>;
    return raw
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> addDownload(Track track) async {
    final list = downloads;
    if (list.any((t) => t.id == track.id)) return;
    list.add(track);
    await _stateBox.put('downloads', list.map((t) => t.toJson()).toList());
  }

  Future<void> removeDownload(String id) async {
    final list = downloads.where((t) => t.id != id).toList();
    await _stateBox.put('downloads', list.map((t) => t.toJson()).toList());
  }

  /// Allinea l'elenco a cio' che c'e' davvero su disco.
  Future<void> reconcileDownloads(
    Set<String> onDisk, {
    String Function(String id)? audioIdOf,
  }) async {
    // Il file porta l'id dell'audio, che per un videoclip e' quello della
    // sua versione canzone: si guarda l'uno e l'altro.
    final list = downloads
        .where(
          (t) =>
              onDisk.contains(t.id) ||
              onDisk.contains(audioIdOf?.call(t.id) ?? t.id),
        )
        .toList();
    if (list.length == downloads.length) return;
    await _stateBox.put('downloads', list.map((t) => t.toJson()).toList());
  }

  // --- Favorites ---

  List<Track> get favorites {
    final raw =
        _favoritesBox.get('tracks', defaultValue: <dynamic>[]) as List<dynamic>;
    return raw
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  bool isFavorite(String id) =>
      _favoritesBox.containsKey('tracks') && (favorites.any((t) => t.id == id));

  Future<void> addFavorite(Track track) async {
    final list = favorites;
    if (list.any((t) => t.id == track.id)) return;
    list.add(track);
    await _favoritesBox.put('tracks', list.map((t) => t.toJson()).toList());
    await mark('fav', track.id);
  }

  Future<void> removeFavorite(String id) async {
    final list = favorites.where((t) => t.id != id).toList();
    await _favoritesBox.put('tracks', list.map((t) => t.toJson()).toList());
    await bury('fav', id);
  }

  /// Rimette un brano tolto dai preferiti dov'era, con la sua data.
  ///
  /// E' l'"Annulla" dopo averlo tolto: passando da [addFavorite] finirebbe
  /// in fondo e con la data di adesso, cioe' in cima ai "Recently Added"
  /// come se fosse appena stato messo.
  Future<void> restoreFavorite(Track track, int index, int? addedAt) async {
    final list = favorites;
    if (list.any((t) => t.id == track.id)) return;
    list.insert(index.clamp(0, list.length), track);
    await _favoritesBox.put('tracks', list.map((t) => t.toJson()).toList());
    await mark('fav', track.id, addedAt);
  }

  /// Aggiunge in blocco brani piaciuti importati da fuori, ognuno con la
  /// sua data, in testa alla lista: la lista cresce in coda, quindi la
  /// testa e' il posto dei piu' vecchi. Una scrittura sola per la lista e
  /// una per le date, non ottocento.
  ///
  /// [dates] corregge la data di piaciuti che c'erano gia'.
  Future<void> importFavorites(
    List<Track> tracks,
    List<int> addedAt, {
    Map<String, int> dates = const {},
  }) async {
    final list = favorites;
    final have = {for (final t in list) t.id};
    final fresh = <Track>[];
    final marksNow = marks('fav')..addAll(dates);
    final gravesNow = graves('fav');
    for (var i = 0; i < tracks.length; i++) {
      if (!have.add(tracks[i].id)) continue;
      fresh.add(tracks[i]);
      marksNow[tracks[i].id] = addedAt[i];
      gravesNow.remove(tracks[i].id);
    }
    // Il piu' vecchio in testa, come se fossero stati aggiunti in ordine.
    await _favoritesBox.put('tracks', [
      for (final t in fresh.reversed) t.toJson(),
      for (final t in list) t.toJson(),
    ]);
    await setMarks('fav', marksNow);
    await setGraves('fav', gravesNow);
  }

  /// Come e' ordinata una raccolta: il nome di un `SongSort`.
  ///
  /// [collection] e' "liked" per i piaciuti, l'id di una playlist per le
  /// playlist: ognuna ricorda il suo, come in Apple.
  String? songSort(String collection) =>
      (_stateBox.get('song_sort') as Map?)?[collection] as String?;

  Future<void> setSongSort(String collection, String value) {
    final all = Map<String, dynamic>.from(
      (_stateBox.get('song_sort') as Map?) ?? const {},
    )..[collection] = value;
    return _stateBox.put('song_sort', all);
  }

  /// Updates the stored duration of a favorite track (keeps the list
  /// in sync when the player learns the real duration of a song).
  Future<void> updateFavoriteDuration(String id, Duration duration) async {
    final list = favorites;
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == id && list[i].duration != duration) {
        list[i] = list[i].copyWith(duration: duration);
        changed = true;
      }
    }
    if (changed) {
      await _favoritesBox.put('tracks', list.map((t) => t.toJson()).toList());
    }
  }

  // --- Duration cache (persistent, survives restarts) ---

  /// Known track durations keyed by video id.
  Map<String, Duration> get durationCache {
    final raw = _durationsBox.toMap();
    return raw.map((k, v) => MapEntry(k, Duration(seconds: v as int)));
  }

  Future<void> saveDuration(String id, Duration duration) async {
    if (_durationsBox.get(id) == duration.inSeconds) return;
    await _durationsBox.put(id, duration.inSeconds);
  }

  // --- Da dove prendere l'audio (persistente) ---

  /// Per ogni videoclip gia' controllato, la sua versione canzone (o se
  /// stesso, quando non ce n'e' una).
  Map<String, String> get audioIds =>
      _audioIdsBox.toMap().map((k, v) => MapEntry(k as String, v as String));

  /// La versione della regola che abbina video e canzoni.
  ///
  /// Un "nessuna canzone" vale per la regola che l'ha deciso: quando la
  /// regola impara a riconoscere piu' casi — le radio edit — i video
  /// scartati prima vanno riprovati, non lasciati scartati per sempre.
  /// Si dimenticano solo quelli: gli abbinamenti trovati restano.
  Future<void> retireUnmatchedBefore(int version) async {
    if ((_stateBox.get('song_matcher') as int? ?? 1) >= version) return;
    final stale = [
      for (final e in _audioIdsBox.toMap().entries)
        if (e.key == e.value) e.key,
    ];
    await _audioIdsBox.deleteAll(stale);
    await _stateBox.put('song_matcher', version);
  }

  /// I dati della versione canzone di ogni video riconosciuto, con l'id
  /// del video: servono a rivestire i brani salvati.
  Map<String, Track> get songVersions => _songVersionsBox.toMap().map(
    (k, v) => MapEntry(
      k as String,
      Track.fromJson(Map<String, dynamic>.from(v as Map)),
    ),
  );

  Future<void> saveAudioId(String id, String audioId, [Track? song]) async {
    if (song != null) await _songVersionsBox.put(id, song.toJson());
    if (_audioIdsBox.get(id) == audioId) return;
    await _audioIdsBox.put(id, audioId);
  }

  // --- YouTube cookie (login) ---

  /// YouTube login cookie. When present, stream requests are sent with it:
  /// a signed-in session is trusted by YouTube and serves full-length
  /// streams instead of the ~1 MiB truncated ones handed to anonymous
  /// clients flagged by the anti-bot.
  String? get youtubeCookie {
    final v = _stateBox.get('youtube_cookie');
    return v is String && v.isNotEmpty ? v : null;
  }

  Future<void> setYoutubeCookie(String? cookie) async {
    if (cookie == null || cookie.trim().isEmpty) {
      await _stateBox.delete('youtube_cookie');
    } else {
      await _stateBox.put('youtube_cookie', cookie.trim());
    }
  }

  // --- Recently played ---

  List<Track> get recentlyPlayed {
    final raw =
        _recentBox.get('tracks', defaultValue: <dynamic>[]) as List<dynamic>;
    return raw
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> addRecentlyPlayed(Track track) async {
    final list = recentlyPlayed;
    list.removeWhere((t) => t.id == track.id);
    list.insert(0, track);
    if (list.length > 30) list.removeRange(30, list.length);
    await _recentBox.put('tracks', list.map((t) => t.toJson()).toList());
    await mark('recent', track.id);
  }

  // --- Search history ---

  List<String> get searchHistory {
    final raw =
        _historyBox.get('queries', defaultValue: <dynamic>[]) as List<dynamic>;
    return raw.cast<String>();
  }

  Future<void> addSearchQuery(String query) async {
    if (query.trim().isEmpty) return;
    final list = searchHistory;
    list.remove(query);
    list.insert(0, query);
    if (list.length > 20) list.removeRange(20, list.length);
    await _historyBox.put('queries', list);
  }

  Future<void> removeSearchQuery(String query) async {
    final list = searchHistory..remove(query);
    await _historyBox.put('queries', list);
  }

  Future<void> clearSearchHistory() => _historyBox.put('queries', <String>[]);

  /// Una volta sola: riporta ogni ascolto gia' registrato sotto la durata
  /// del suo brano. Prima si contava il tempo dall'orologio, pause comprese,
  /// e ne erano usciti ascolti da decine di ore. Il totale di ogni brano
  /// perde esattamente cio' che i suoi ascolti perdono, e non supera mai
  /// quanti ascolti per la durata.
  Future<void> _capListens() async {
    if (_stateBox.get('listens_capped') == true) return;
    final durations = durationCache;
    final known = statTracksJson;
    int capOf(String id) => listenCap(
      durations[id]?.inSeconds ?? (known[id]?['duration'] as num?)?.toInt(),
    );

    final excess = <String, int>{};
    final rows = <List<Object>>[];
    var changed = false;
    for (final v in _playLogBox.values) {
      if (v is! List || v.length < 3) continue;
      final id = v[0] as String;
      final secs = v[2] as int;
      final cap = capOf(id);
      if (secs > cap) {
        excess[id] = (excess[id] ?? 0) + secs - cap;
        changed = true;
      }
      rows.add([id, v[1] as int, secs > cap ? cap : secs]);
    }
    if (changed) {
      await _playLogBox.clear();
      await _playLogBox.addAll(rows);
    }

    final plays = Map<String, dynamic>.from(
      _statsBox.get('plays', defaultValue: <dynamic, dynamic>{}) as Map,
    );
    for (final e in plays.entries.toList()) {
      final entry = Map<String, dynamic>.from(e.value as Map);
      final count = entry['count'] as int? ?? 0;
      var total = (entry['totalSeconds'] as int? ?? 0) - (excess[e.key] ?? 0);
      final ceiling = count * capOf(e.key);
      if (total > ceiling) total = ceiling;
      if (total < 0) total = 0;
      if (total != entry['totalSeconds']) {
        entry['totalSeconds'] = total;
        plays[e.key] = entry;
        changed = true;
      }
    }
    if (changed) await _statsBox.put('plays', plays);
    await _stateBox.put('listens_capped', true);
  }

  // --- Statistics ---  /// Increments the play count for a track and records the listen duration.
  Future<void> recordPlay(
    String trackId, {
    Duration? listenDuration,
    Track? track,
  }) async {
    // Ogni ascolto anche col suo momento, in un registro a parte: i totali
    // qui sotto dicono quanto in tutto, ma non quando, e senza il quando
    // non esiste "questo mese". Un box a sole aggiunte, cosi' registrare
    // costa uguale al primo ascolto e al ventimillesimo.
    // Mai piu' della durata del brano: vedi listenCap.
    final cap = listenCap(
      track?.duration?.inSeconds ?? durationCache[trackId]?.inSeconds,
    );
    final heard = listenDuration?.inSeconds ?? 0;
    listenDuration = Duration(seconds: heard > cap ? cap : heard);
    await _playLogBox.add([
      trackId,
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      listenDuration.inSeconds,
    ]);
    // E com'era fatto il brano: le statistiche lo cercavano solo fra
    // recenti e preferiti, e un brano uscito da entrambi spariva dalla
    // classifica pur restando nei totali.
    if (track != null) await _statTracksBox.put(track.id, track.toJson());
    // Must clone the map so Hive detects the change (same-reference puts
    // are silently ignored by Hive).
    final raw = _statsBox.get('plays') as Map? ?? {};
    final plays = Map<String, dynamic>.from(raw);
    final entry = Map<String, dynamic>.from((plays[trackId] as Map?) ?? {});
    entry['count'] = (entry['count'] as int? ?? 0) + 1;
    entry['lastPlayed'] = DateTime.now().millisecondsSinceEpoch;
    entry['totalSeconds'] =
        (entry['totalSeconds'] as int? ?? 0) + listenDuration.inSeconds;
    plays[trackId] = entry;
    await _statsBox.put('plays', plays);
  }

  /// Gli ascolti uno per uno: (id, quando, secondi).
  List<(String, DateTime, int)> get playLog => [
    for (final v in _playLogBox.values)
      if (v is List && v.length >= 3)
        (
          v[0] as String,
          DateTime.fromMillisecondsSinceEpoch((v[1] as int) * 1000),
          v[2] as int,
        ),
  ];

  /// Il registro come lo trasporta la sincronizzazione: per brano, una
  /// coppia [quando, secondi] per ascolto. Raggruppato perche' l'id, che
  /// e' la parte lunga, si scrive una volta sola invece che a ogni riga.
  Map<String, List<List<int>>> get playLogByTrack {
    final out = <String, List<List<int>>>{};
    for (final v in _playLogBox.values) {
      if (v is! List || v.length < 3) continue;
      (out[v[0] as String] ??= []).add([v[1] as int, v[2] as int]);
    }
    return out;
  }

  int get playLogLength => _playLogBox.length;

  /// Sostituisce il registro con quello fuso. Solo dalla sincronizzazione.
  Future<void> replacePlayLog(Map<String, List<List<int>>> log) async {
    final rows = [
      for (final e in log.entries)
        for (final p in e.value) [e.key, p[0], p[1]],
    ]..sort((a, b) => (a[1] as int).compareTo(b[1] as int));
    await _playLogBox.clear();
    await _playLogBox.addAll(rows);
  }

  /// Aggiunge i brani che conosceva l'altro dispositivo. Quelli gia' noti
  /// qui restano come sono: sono stati visti per ultimi da questo.
  Future<void> addStatTracks(Map<String, Map<String, dynamic>> tracks) async {
    final missing = {
      for (final e in tracks.entries)
        if (!_statTracksBox.containsKey(e.key)) e.key: e.value,
    };
    if (missing.isNotEmpty) await _statTracksBox.putAll(missing);
  }

  Map<String, Map<String, dynamic>> get statTracksJson =>
      _statTracksBox.toMap().map(
        (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
      );

  /// I brani ascoltati, come erano l'ultima volta che sono suonati.
  Map<String, Track> get statTracks => _statTracksBox.toMap().map(
    (k, v) => MapEntry(
      k as String,
      Track.fromJson(Map<String, dynamic>.from(v as Map)),
    ),
  );

  Map<String, dynamic> getPlayStats(String trackId) {
    final plays =
        _statsBox.get('plays', defaultValue: <dynamic, dynamic>{}) as Map;
    return Map<String, dynamic>.from(plays[trackId] ?? {});
  }

  Map<String, dynamic> getAllPlayStats() {
    final plays =
        _statsBox.get('plays', defaultValue: <dynamic, dynamic>{}) as Map;
    return plays.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
  }

  // --- User Playlists ---

  List<Map<String, dynamic>> get playlists {
    final raw =
        _playlistsBox.get('user_playlists', defaultValue: <dynamic>[])
            as List<dynamic>;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Segna la playlist come modificata adesso.
  Future<void> _touch(Map<String, dynamic> pl) async {
    final id = pl['id'] as String?;
    if (id != null) await mark('pl', id);
  }

  Future<void> savePlaylists(List<Map<String, dynamic>> pls) async {
    await _playlistsBox.put('user_playlists', pls);
  }

  Future<void> createPlaylist(String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Un id stabile: le playlist erano indirizzate per posizione, e una
    // posizione non sopravvive a due dispositivi che riordinano.
    final id = 'pl_${now}_${name.hashCode.toUnsigned(16).toRadixString(16)}';
    final list = playlists;
    list.add({'id': id, 'name': name, 'tracks': <dynamic>[], 'createdAt': now});
    await savePlaylists(list);
    await mark('pl', id);
  }

  Future<void> deletePlaylist(int index) async {
    final list = playlists;
    if (index >= 0 && index < list.length) {
      final id = list[index]['id'] as String?;
      list.removeAt(index);
      await savePlaylists(list);
      if (id != null) await bury('pl', id);
    }
  }

  Future<void> renamePlaylist(int index, String newName) async {
    final list = playlists;
    if (index >= 0 && index < list.length) {
      list[index]['name'] = newName;
      await savePlaylists(list);
      await _touch(list[index]);
    }
  }

  Future<void> addTrackToPlaylist(int index, Track track) async {
    final list = playlists;
    if (index >= 0 && index < list.length) {
      final tracks = (list[index]['tracks'] as List?) ?? [];
      final ids = tracks.map((t) => (t as Map)['id']).toList();
      if (!ids.contains(track.id)) {
        tracks.add(track.toJson());
        list[index]['tracks'] = tracks;
        await savePlaylists(list);
        await _touch(list[index]);
      }
    }
  }

  Future<void> removeTrackFromPlaylist(int index, String trackId) async {
    final list = playlists;
    if (index >= 0 && index < list.length) {
      final tracks = (list[index]['tracks'] as List?) ?? [];
      tracks.removeWhere((t) => (t as Map)['id'] == trackId);
      list[index]['tracks'] = tracks;
      await savePlaylists(list);
      await _touch(list[index]);
    }
  }

  /// Rimette un brano tolto dalla playlist alla sua posizione: l'"Annulla"
  /// dopo averlo tolto, che in fondo alla lista lo sposterebbe.
  Future<void> insertTrackInPlaylist(int index, Track track, int at) async {
    final list = playlists;
    if (index < 0 || index >= list.length) return;
    final tracks = (list[index]['tracks'] as List?) ?? [];
    if (tracks.any((t) => (t as Map)['id'] == track.id)) return;
    tracks.insert(at.clamp(0, tracks.length), track.toJson());
    list[index]['tracks'] = tracks;
    await savePlaylists(list);
    await _touch(list[index]);
  }

  /// Riscrive i brani della playlist in un ordine nuovo: il riordino per
  /// i passaggi, e il suo "Annulla".
  Future<void> setPlaylistTracks(int index, List<Track> tracks) async {
    final list = playlists;
    if (index < 0 || index >= list.length) return;
    list[index]['tracks'] = [for (final t in tracks) t.toJson()];
    await savePlaylists(list);
    await _touch(list[index]);
  }

  /// L'id stabile della playlist, per ricordarne l'ordinamento.
  String? playlistId(int index) {
    final list = playlists;
    return index >= 0 && index < list.length
        ? list[index]['id'] as String?
        : null;
  }

  List<Track> getPlaylistTracks(int index) {
    final list = playlists;
    if (index >= 0 && index < list.length) {
      final raw = (list[index]['tracks'] as List?) ?? [];
      return raw
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }

  // --- Queue persistence ---

  List<Track> get savedQueue {
    final raw =
        _stateBox.get('queue', defaultValue: <dynamic>[]) as List<dynamic>;
    return raw
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveQueue(List<Track> queue) async {
    await _stateBox.put('queue', queue.map((t) => t.toJson()).toList());
  }

  // --- Playback session ---
  //
  // Everything needed to put the player back where it was, except a stream
  // URL: YouTube's carry an `expire` parameter measured in hours, and the
  // local proxy binds a fresh ephemeral port on every launch. Restoring must
  // always resolve the audio again.

  Map<String, dynamic> get playbackSession {
    final raw = _stateBox.get('session');
    if (raw is! Map) return {};
    return Map<String, dynamic>.from(raw);
  }

  Future<void> savePlaybackSession({
    required int index,
    required Duration position,
    required Duration duration,
    required bool shuffle,
    required String repeat,
    required Duration crossfade,
    required bool radio,
    bool automix = false,
  }) async {
    await _stateBox.put('session', {
      'index': index,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'shuffle': shuffle,
      'repeat': repeat,
      'crossfadeMs': crossfade.inMilliseconds,
      'radio': radio,
      'automix': automix,
    });
  }

  Future<void> clearPlaybackSession() async {
    await _stateBox.delete('session');
    await _stateBox.delete('queue');
  }

  // --- Volume dei brani, per AutoMix ---

  /// Il `loudnessDb` di YouTube per ogni brano gia' risolto. Serve anche a
  /// quelli che suonano da file, per cui non si chiede niente a YouTube.
  double? loudnessOf(String id) => (_loudnessBox.get(id) as num?)?.toDouble();

  Future<void> saveLoudness(String id, double db) async {
    if (_loudnessBox.get(id) == db) return;
    await _loudnessBox.put(id, db);
  }

  // --- Griglie dei battiti, per AutoMix ---

  /// L'analisi ritmica di un brano, gia' fatta: si fa una volta sola.
  Map<String, dynamic>? beatGridJson(String id) {
    final raw = _beatsBox.get(id);
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> saveBeatGrid(String id, Map<String, dynamic> json) =>
      _beatsBox.put(id, json);

  // --- Equalizer ---

  List<double> get eqGains {
    final raw = _stateBox.get('eq_gains');
    if (raw is! List) return const [];
    return raw.map((e) => (e as num).toDouble()).toList();
  }

  Future<void> saveEqGains(List<double> gains) async {
    await _stateBox.put('eq_gains', gains);
  }

  double get eqPreamp => (_stateBox.get('eq_preamp') as num?)?.toDouble() ?? 0;

  Future<void> saveEqPreamp(double db) => _stateBox.put('eq_preamp', db);

  bool get eqEnabled => _stateBox.get('eq_enabled') as bool? ?? true;

  Future<void> saveEqEnabled(bool on) => _stateBox.put('eq_enabled', on);

  /// I preset salvati da te: nome e guadagni.
  List<Map<String, dynamic>> get eqPresets => [
    for (final p in (_stateBox.get('eq_presets') as List?) ?? const [])
      Map<String, dynamic>.from(p as Map),
  ];

  Future<void> saveEqPresets(List<Map<String, dynamic>> presets) =>
      _stateBox.put('eq_presets', presets);

  /// I testi gia' scaricati, per titolo e artista: si leggono anche senza
  /// rete. Un testo pesa pochi chilobyte, e un brano ne ha uno solo.
  Map? cachedLyrics(String key) {
    final raw = _lyricsBox.get(key);
    return raw is Map ? raw : null;
  }

  Future<void> saveLyrics(String key, Map<String, Object> json) =>
      _lyricsBox.put(key, json);

  /// Discover Weekly e i Daily Mix gia' calcolati, con la settimana e il
  /// giorno a cui valgono: si rifanno solo quando scadono.
  Map? get discovery {
    final raw = _stateBox.get('discovery');
    return raw is Map ? raw : null;
  }

  Future<void> saveDiscovery(Map<String, Object?> data) =>
      _stateBox.put('discovery', data);

  /// La copertina animata nel player: accesa di serie.
  bool get motionCover => _stateBox.get('motion_cover') as bool? ?? true;

  Future<void> setMotionCover(bool value) =>
      _stateBox.put('motion_cover', value);

  /// Quanto si muovono le macchie con la musica in ascolto: 0 spente, 1
  /// l'effetto di serie, fino a 2 il doppio.
  double get spotsMusic =>
      (_stateBox.get('spots_music_level') as num?)?.toDouble() ?? 1;

  Future<void> setSpotsMusic(double value) =>
      _stateBox.put('spots_music_level', value);

  /// Anche i testi che crescono sui colpi della musica: spento di serie.
  bool get textPulse => _stateBox.get('text_pulse') as bool? ?? false;

  Future<void> setTextPulse(bool value) => _stateBox.put('text_pulse', value);

  /// L'identita' di questo dispositivo per Crocuta Connect: fissa, cosi'
  /// gli altri lo riconoscono anche se cambia indirizzo.
  String? get connectId => _stateBox.get('connect_id') as String?;

  Future<void> setConnectId(String id) => _stateBox.put('connect_id', id);

  /// Il nome scelto per questo dispositivo in Crocuta Connect.
  String? get connectName => _stateBox.get('connect_name') as String?;

  Future<void> setConnectName(String name) =>
      _stateBox.put('connect_name', name);

  /// Crocuta Connect acceso: di serie si'.
  bool get connectEnabled => _stateBox.get('connect_enabled') as bool? ?? true;

  Future<void> setConnectEnabled(bool value) =>
      _stateBox.put('connect_enabled', value);

  /// L'ordinamento delle pagine della libreria che non sono raccolte di
  /// brani — "albums", "artists", "playlists" — come lo scrive
  /// `LibraryView.encodeSort`. I brani usano [songSort].
  String? librarySort(String page) =>
      (_stateBox.get('library_sort') as Map?)?[page] as String?;

  Future<void> setLibrarySort(String page, String value) {
    final all = Map<String, dynamic>.from(
      (_stateBox.get('library_sort') as Map?) ?? const {},
    )..[page] = value;
    return _stateBox.put('library_sort', all);
  }

  /// I filtri accesi di una pagina ("liked", "downloads"): i nomi dei
  /// `SongFilter`. Restano dopo il riavvio, come l'ordinamento.
  Set<String> libraryFilters(String page) {
    final list = (_stateBox.get('library_filters') as Map?)?[page] as List?;
    return {for (final f in list ?? const []) f.toString()};
  }

  Future<void> setLibraryFilters(String page, Set<String> filters) {
    final all = Map<String, dynamic>.from(
      (_stateBox.get('library_filters') as Map?) ?? const {},
    )..[page] = filters.toList();
    return _stateBox.put('library_filters', all);
  }

  // --- Import da Spotify ---
  //
  // Solo su questo dispositivo: la sincronizzazione non le porta altrove
  // (i token valgono per l'app Spotify di chi li ha chiesti), e lo stato
  // dell'import e' un JSON solo, cosi' si riscrive intero dopo ogni passo.

  /// Il Client ID dell'app Spotify che ognuno si crea.
  String? get spotifyClientId => _stateBox.get('spotify_client_id') as String?;

  Future<void> setSpotifyClientId(String? id) => id == null
      ? _stateBox.delete('spotify_client_id')
      : _stateBox.put('spotify_client_id', id);

  /// I token di Spotify (accesso e refresh), come JSON.
  String? get spotifyTokens => _stateBox.get('spotify_tokens') as String?;

  Future<void> setSpotifyTokens(String? json) => json == null
      ? _stateBox.delete('spotify_tokens')
      : _stateBox.put('spotify_tokens', json);

  /// L'import in corso o l'ultimo finito, come JSON: vedi
  /// SpotifyImportState.
  String? get spotifyImport => _stateBox.get('spotify_import') as String?;

  Future<void> setSpotifyImport(String? json) => json == null
      ? _stateBox.delete('spotify_import')
      : _stateBox.put('spotify_import', json);
}
