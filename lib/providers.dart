import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/album.dart';
import 'models/artist.dart';
import 'models/explore.dart';
import 'models/lyrics.dart';
import 'models/playlist.dart';
import 'models/track.dart';
import 'services/dominant_color.dart';
import 'services/downloads_controller.dart';
import 'services/eq_controller.dart';
import 'services/follows_controller.dart';
import 'services/now_playing_service.dart';
import 'services/pot_service.dart';
import 'services/player_controller.dart';
import 'services/player_state.dart';
import 'services/song_preloader.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/stream_proxy.dart';
import 'services/youtube_service.dart';

/// Lazily-created YouTube service (single instance).
///
/// Seeded with the persisted duration cache and writes every newly
/// resolved duration back to disk, so durations survive restarts and
/// re-searches barely cost anything.
final youtubeServiceProvider = Provider<YouTubeService>((ref) {
  final storage = ref.read(storageServiceProvider);
  final service = YouTubeService(
    initialDurationCache: storage.durationCache,
    onDurationResolved: (id, d) => storage.saveDuration(id, d),
    // Ogni brano che ripassa dalla rete riallinea la sua copia salvata,
    // cosi' preferiti e playlist non restano fermi a com'era l'analisi il
    // giorno in cui li hai aggiunti.
    onTracksSeen: (tracks) async {
      if (!await storage.refreshCachedTracks(tracks)) return;
      ref.invalidate(favoritesProvider);
      ref.invalidate(recentlyPlayedProvider);
      ref.invalidate(playlistsProvider);
    },
    initialAudioIds: storage.audioIds,
    initialSongVersions: storage.songVersions,
    onAudioIdResolved: storage.saveAudioId,
    cookie: storage.youtubeCookie,
  );
  // Collega il generatore poToken: i client web (WEB_SAFARI, WEB_REMIX,
  // TVHTML5) ne hanno bisogno per stream completi.
  final potService = ref.read(potServiceProvider);
  service.potProvider = potService.generatePot;
  service.webVisitorDataProvider = potService.webVisitorData;
  ref.onDispose(service.dispose);
  return service;
});

/// Single storage instance, initialized in main().
final storageServiceProvider = Provider<StorageService>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Generatore poToken (BotGuard via WebView nascosta). Avviato lazy:
/// la webview carica youtube.com solo quando serve un token.
final potServiceProvider = Provider<PotService>((ref) {
  final pot = PotService();
  ref.onDispose(pot.dispose);
  return pot;
});

/// Local HTTP proxy that makes YouTube stream URLs playable by the player.
final streamProxyProvider = Provider<StreamProxy>((ref) {
  final proxy = StreamProxy();
  ref.onDispose(proxy.dispose);
  return proxy;
});

/// Downloads whole songs to local cache (stitching Google's windows)
/// so playback happens from a file with no possible interruptions.
final songPreloaderProvider = Provider<SongPreloader>((ref) {
  final preloader = SongPreloader(
    resolver: ref.read(youtubeServiceProvider).resolver,
  );
  ref.onDispose(preloader.dispose);
  return preloader;
});

/// iOS lock screen / Control Center playback controls.
final nowPlayingProvider = Provider<NowPlayingService>((ref) {
  final service = NowPlayingService();
  ref.onDispose(service.dispose);
  return service;
});

/// Global player state.
final playerProvider = NotifierProvider<PlayerController, PlayerState>(
  PlayerController.new,
);

/// 5-band equalizer applied to libmpv's audio chain.
final eqProvider = NotifierProvider<EqController, EqState>(EqController.new);

/// Dominant color of a cover image (used as the player backdrop).
/// Gli artisti che segui.
final followsProvider =
    NotifierProvider<FollowsController, List<FollowedArtist>>(
      FollowsController.new,
    );

/// Se scaricare in anticipo il brano successivo.
final autoPreloadProvider = NotifierProvider<AutoPreloadController, bool>(
  AutoPreloadController.new,
);

/// La copertina animata: il videoclip muto in loop al posto della
/// copertina ferma, quando il brano ne ha uno.
final motionCoverProvider = NotifierProvider<MotionCoverController, bool>(
  MotionCoverController.new,
);

class MotionCoverController extends Notifier<bool> {
  @override
  bool build() => ref.read(storageServiceProvider).motionCover;

  Future<void> set(bool value) async {
    await ref.read(storageServiceProvider).setMotionCover(value);
    state = value;
  }
}

class AutoPreloadController extends Notifier<bool> {
  @override
  bool build() => ref.read(storageServiceProvider).autoPreload;

  Future<void> set(bool value) async {
    await ref.read(storageServiceProvider).setAutoPreload(value);
    state = value;
  }
}

/// I brani scaricati apposta.
final downloadsProvider = NotifierProvider<DownloadsController, DownloadsState>(
  DownloadsController.new,
);

/// La sincronizzazione fra dispositivi. Spenta finche' nelle Impostazioni
/// non ci sono indirizzo e segreto.
final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.read(storageServiceProvider));
});

/// Quando la sincronizzazione e' riuscita l'ultima volta; si aggiorna
/// quando la si invalida dopo una passata.
final lastSyncProvider = Provider<DateTime?>(
  (ref) => ref.read(storageServiceProvider).lastSync,
);

/// Esegue una passata e ricarica cio' che puo' essere cambiato.
Future<SyncOutcome> runSync(WidgetRef ref) async {
  final outcome = await ref.read(syncServiceProvider).sync();
  if (outcome != SyncOutcome.done) return outcome;
  ref.invalidate(favoritesProvider);
  ref.invalidate(recentlyPlayedProvider);
  ref.invalidate(playlistsProvider);
  ref.invalidate(followsProvider);
  ref.invalidate(statsProvider);
  ref.invalidate(lastSyncProvider);
  return outcome;
}

/// Entrambi i colori della copertina, estratti insieme.
final artworkPaletteProvider = FutureProvider.autoDispose
    .family<ArtworkPalette, String>((ref, url) => paletteOf(url));

/// Il colore dello sfondo sfocato.
final backdropColorProvider = FutureProvider.autoDispose.family<Color?, String>(
  (ref, url) async =>
      (await ref.watch(artworkPaletteProvider(url).future)).backdrop,
);

/// Il colore da cui ricavare l'accento: il piu' vivo della copertina, con
/// il dominante come ripiego quando la copertina non ha nessuna tinta.
final vividColorProvider = FutureProvider.autoDispose.family<Color?, String>((
  ref,
  url,
) async {
  final palette = await ref.watch(artworkPaletteProvider(url).future);
  return palette.vivid ?? palette.backdrop;
});

/// Artist page fetched from YouTube Music.
final artistPageProvider = FutureProvider.autoDispose
    .family<ArtistPage, String>(
      (ref, browseId) =>
          ref.read(youtubeServiceProvider).getArtistPage(browseId),
    );

/// Album page fetched from YouTube Music.
final albumPageProvider = FutureProvider.autoDispose.family<Album, String>(
  (ref, browseId) => ref.read(youtubeServiceProvider).getAlbumPage(browseId),
);

/// Cosa mostrare nella ricerca finche' non si e' scritto niente.
///
/// Non autoDispose: costa tre richieste, e cambia una volta al giorno. Che
/// si ricarichi ogni volta che si passa da un'altra scheda sarebbe uno
/// spreco che si vede — la pagina resterebbe a girare a vuoto ogni volta.
final exploreProvider = FutureProvider<ExplorePage>(
  (ref) => ref.read(youtubeServiceProvider).getExplore(),
);

/// Le categorie da sfogliare: umori e generi di YouTube Music.
final categoriesProvider = FutureProvider<List<CategoryGroup>>(
  (ref) => ref.read(youtubeServiceProvider).getCategories(),
);

/// Le playlist di una categoria, a file come le mostra YouTube Music.
///
/// Non si butta alla chiusura: la stessa risposta da' la copertina alla
/// tessera e le file alla pagina, e aprendo una tessera gia' vista non si
/// deve riscaricare niente.
final categoryProvider =
    FutureProvider.family<List<(String, List<AlbumCard>)>, String>(
      (ref, params) => ref.read(youtubeServiceProvider).getCategory(params),
    );

/// La versione completa di una sezione della pagina artista.
///
/// Il risultato e' `List<AlbumCard>` o `List<Track>` a seconda della
/// sezione: sono due forme diverse — copertine ed elenco — e un tipo solo
/// costringerebbe a inventare una conversione fra le due.
final sectionProvider = FutureProvider.autoDispose
    .family<List<Object>, SectionLink>((ref, link) {
      final service = ref.read(youtubeServiceProvider);
      return link.songs
          ? service.getSectionSongs(link.browseId, params: link.params)
          : service.getSectionGrid(link.browseId, params: link.params);
    });

/// Playlist page fetched from YouTube Music.
final playlistPageProvider = FutureProvider.autoDispose
    .family<Playlist, String>(
      (ref, browseId) =>
          ref.read(youtubeServiceProvider).getPlaylistPage(browseId),
    );

/// Suggested songs for a video (key: "videoId|artist").
final upNextProvider = FutureProvider.autoDispose.family<List<Track>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  return ref
      .read(youtubeServiceProvider)
      .getUpNext(parts[0], artist: parts.length > 1 ? parts[1] : null);
});

/// Synced lyrics for a track (key: "title|artist").
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  if (parts.length < 2) return Future.value(null);
  return lyricsFor(ref, title: parts[0], artist: parts[1]);
});

/// Il testo di un brano: quello salvato se c'e', altrimenti dalla rete, e
/// lo si salva per la prossima volta — anche senza connessione.
///
/// Un testo che non si trova non si ricorda: puo' comparire domani.
Future<Lyrics?> lyricsFor(
  Ref ref, {
  required String title,
  required String artist,
}) async {
  final storage = ref.read(storageServiceProvider);
  final key = '$title|$artist';
  final saved = storage.cachedLyrics(key);
  if (saved != null) {
    try {
      final lyrics = Lyrics.fromJson(saved);
      if (lyrics.lines.isNotEmpty) return lyrics;
    } catch (_) {}
  }
  final fresh = await ref
      .read(youtubeServiceProvider)
      .getLyrics(title: title, artist: artist);
  if (fresh != null && fresh.lines.isNotEmpty) {
    await storage.saveLyrics(key, fresh.toJson());
  }
  return fresh;
}

/// Result of a search request, split into the sections shown by the UI
/// (artists, songs, albums, playlists) like in major music apps.
class SearchResult {
  final String query;
  final List<Track> tracks;
  final List<AlbumCard> artists;
  final List<AlbumCard> albums;
  final List<AlbumCard> playlists;
  final bool isLoading;
  final String? error;

  const SearchResult({
    this.query = '',
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  SearchResult copyWith({
    String? query,
    List<Track>? tracks,
    List<AlbumCard>? artists,
    List<AlbumCard>? albums,
    List<AlbumCard>? playlists,
    bool? isLoading,
    String? error,
  }) {
    return SearchResult(
      query: query ?? this.query,
      tracks: tracks ?? this.tracks,
      artists: artists ?? this.artists,
      albums: albums ?? this.albums,
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Holds the current search results.
class SearchController extends Notifier<SearchResult> {
  @override
  SearchResult build() => const SearchResult();

  void clear() => state = const SearchResult();

  Future<void> search(String query) async {
    state = SearchResult(query: query, isLoading: true, error: null);
    // Track search history.
    ref.read(searchHistoryProvider.notifier).add(query);
    try {
      final service = ref.read(youtubeServiceProvider);
      final sections = await service.search(query);
      state = SearchResult(
        query: query,
        tracks: sections.songs,
        artists: sections.artists,
        albums: sections.albums,
        playlists: sections.playlists,
      );
      // The YTM search API omits durations — fill them in the background
      // once they resolve (the list already shows immediately).
      final enriched = await service.enrichDurations(sections.songs);
      if (state.query == query) {
        state = state.copyWith(tracks: enriched);
      }
    } catch (e) {
      state = SearchResult(query: query, error: 'Search failed: \$e');
    }
  }
}

final searchProvider = NotifierProvider<SearchController, SearchResult>(
  SearchController.new,
);

/// Hive-backed list of favorites.
class FavoritesController extends Notifier<List<Track>> {
  bool _enriching = false;

  @override
  List<Track> build() {
    return ref.watch(storageServiceProvider).favorites;
  }

  bool isFavorite(String id) => ref.read(storageServiceProvider).isFavorite(id);

  Future<void> toggle(Track track) async {
    // Qui e non nei pulsanti: i punti da cui si mette un preferito sono
    // quattro — player, menu contestuale, ricerca, elenco preferiti — e un
    // tocco che vibra da una parte e non dall'altra si nota.
    HapticFeedback.lightImpact();
    final storage = ref.read(storageServiceProvider);
    if (storage.isFavorite(track.id)) {
      await storage.removeFavorite(track.id);
    } else {
      // Carry over the duration when the track is currently playing.
      final player = ref.read(playerProvider);
      var t = track;
      if (t.duration == null &&
          player.current?.id == track.id &&
          player.duration > Duration.zero) {
        t = t.copyWith(duration: player.duration);
      }
      await storage.addFavorite(t);
    }
    state = storage.favorites;
  }

  /// Toglie il brano e restituisce come rimetterlo dov'era.
  ///
  /// Per l'"Annulla" dopo lo scorrimento: la posizione e la data vanno
  /// lette prima di toglierlo, dopo non ci sono piu'.
  Future<Future<void> Function()> remove(Track track) async {
    HapticFeedback.mediumImpact();
    final storage = ref.read(storageServiceProvider);
    final index = storage.favorites.indexWhere((t) => t.id == track.id);
    final addedAt = storage.marks('fav')[track.id];
    // Via dalla lista subito, prima di aspettare il disco: la riga tolta
    // scorrendo e' gia' uscita, e se la pagina si ridisegnasse con il
    // brano ancora dentro Dismissible si lamenterebbe di essere tornato.
    state = [
      for (final t in state)
        if (t.id != track.id) t,
    ];
    await storage.removeFavorite(track.id);
    state = storage.favorites;
    return () async {
      await storage.restoreFavorite(track, index, addedAt);
      state = storage.favorites;
    };
  }

  /// Fills in missing durations of stored favorites (from the persistent
  /// cache first, then by resolving them in the background). Keeps the
  /// list showing real times instead of "--:--".
  Future<void> enrichDurations() async {
    if (_enriching) return;
    _enriching = true;
    try {
      final storage = ref.read(storageServiceProvider);
      final favorites = storage.favorites;
      if (favorites.isEmpty) return;

      final missing = favorites.where((t) => t.duration == null).toList();
      if (missing.isEmpty) return;

      final service = ref.read(youtubeServiceProvider);
      final enriched = await service.enrichDurations(favorites);
      for (var i = 0; i < enriched.length; i++) {
        final before = favorites[i];
        final after = enriched[i];
        if (after.duration != null && before.duration != after.duration) {
          await storage.updateFavoriteDuration(before.id, after.duration!);
        }
      }
      state = storage.favorites;
    } finally {
      _enriching = false;
    }
  }
}

final favoritesProvider = NotifierProvider<FavoritesController, List<Track>>(
  FavoritesController.new,
);

/// Recently played tracks.
class RecentlyPlayedController extends Notifier<List<Track>> {
  @override
  List<Track> build() {
    return ref.watch(storageServiceProvider).recentlyPlayed;
  }

  Future<void> add(Track track) async {
    await ref.read(storageServiceProvider).addRecentlyPlayed(track);
    state = ref.read(storageServiceProvider).recentlyPlayed;
  }
}

final recentlyPlayedProvider =
    NotifierProvider<RecentlyPlayedController, List<Track>>(
      RecentlyPlayedController.new,
    );

/// Search history queries.
class SearchHistoryController extends Notifier<List<String>> {
  @override
  List<String> build() {
    return ref.watch(storageServiceProvider).searchHistory;
  }

  Future<void> add(String query) async {
    await ref.read(storageServiceProvider).addSearchQuery(query);
    state = ref.read(storageServiceProvider).searchHistory;
  }

  Future<void> remove(String query) async {
    await ref.read(storageServiceProvider).removeSearchQuery(query);
    state = ref.read(storageServiceProvider).searchHistory;
  }

  Future<void> clear() async {
    await ref.read(storageServiceProvider).clearSearchHistory();
    state = const [];
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryController, List<String>>(
      SearchHistoryController.new,
    );

// ----------------------------------------------------------------------
// Listening statistics
// ----------------------------------------------------------------------

/// Statistics for a single track.
class TrackStats {
  final int playCount;
  final int totalSeconds;
  final DateTime? lastPlayed;

  const TrackStats({
    this.playCount = 0,
    this.totalSeconds = 0,
    this.lastPlayed,
  });
}

/// All play stats keyed by track id.
class StatsController extends Notifier<Map<String, TrackStats>> {
  @override
  Map<String, TrackStats> build() {
    final raw = ref.read(storageServiceProvider).getAllPlayStats();
    return raw.map(
      (k, v) => MapEntry(
        k,
        TrackStats(
          playCount: v['count'] as int? ?? 0,
          totalSeconds: v['totalSeconds'] as int? ?? 0,
          lastPlayed: v['lastPlayed'] != null
              ? DateTime.fromMillisecondsSinceEpoch(v['lastPlayed'] as int)
              : null,
        ),
      ),
    );
  }

  Future<void> recordPlay(
    String trackId, {
    Duration? listenDuration,
    Track? track,
  }) async {
    await ref
        .read(storageServiceProvider)
        .recordPlay(trackId, listenDuration: listenDuration, track: track);
    state = ref
        .read(storageServiceProvider)
        .getAllPlayStats()
        .map(
          (k, v) => MapEntry(
            k,
            TrackStats(
              playCount: v['count'] as int? ?? 0,
              totalSeconds: v['totalSeconds'] as int? ?? 0,
              lastPlayed: v['lastPlayed'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(v['lastPlayed'] as int)
                  : null,
            ),
          ),
        );
  }

  List<MapEntry<String, TrackStats>> topTracks({int limit = 10}) {
    final list = state.entries.toList()
      ..sort((a, b) => b.value.playCount.compareTo(a.value.playCount));
    return list.take(limit).toList();
  }

  int get totalPlays => state.values.fold(0, (s, v) => s + v.playCount);
  int get totalMinutes =>
      state.values.fold(0, (s, v) => s + v.totalSeconds) ~/ 60;
}

final statsProvider =
    NotifierProvider<StatsController, Map<String, TrackStats>>(
      StatsController.new,
    );

// ----------------------------------------------------------------------
// User playlists
// ----------------------------------------------------------------------

/// A user-created playlist.
class UserPlaylist {
  final String name;
  final List<Track> tracks;
  final DateTime? createdAt;

  const UserPlaylist({
    required this.name,
    this.tracks = const [],
    this.createdAt,
  });
}

/// Manages user-created playlists.
class PlaylistsController extends Notifier<List<UserPlaylist>> {
  @override
  List<UserPlaylist> build() {
    final raw = ref.read(storageServiceProvider).playlists;
    return raw.map((p) {
      final tracksRaw = (p['tracks'] as List?) ?? [];
      return UserPlaylist(
        name: p['name'] as String? ?? 'Playlist',
        tracks: tracksRaw
            .map((t) => Track.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList(),
        createdAt: p['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(p['createdAt'] as int)
            : null,
      );
    }).toList();
  }

  Future<void> create(String name) async {
    await ref.read(storageServiceProvider).createPlaylist(name);
    state = _reload();
  }

  Future<void> delete(int index) async {
    await ref.read(storageServiceProvider).deletePlaylist(index);
    state = _reload();
  }

  Future<void> rename(int index, String newName) async {
    await ref.read(storageServiceProvider).renamePlaylist(index, newName);
    state = _reload();
  }

  Future<void> addTrack(int index, Track track) async {
    await ref.read(storageServiceProvider).addTrackToPlaylist(index, track);
    state = _reload();
  }

  Future<void> removeTrack(int index, String trackId) async {
    await ref
        .read(storageServiceProvider)
        .removeTrackFromPlaylist(index, trackId);
    state = _reload();
  }

  /// I brani della playlist in un ordine nuovo.
  Future<void> setTracks(int index, List<Track> tracks) async {
    await ref.read(storageServiceProvider).setPlaylistTracks(index, tracks);
    state = _reload();
  }

  /// Toglie il brano e restituisce come rimetterlo dov'era, per l'"Annulla".
  ///
  /// Via dallo stato subito, prima del disco: la riga tolta scorrendo e'
  /// gia' uscita, e Dismissible non vuole rivederla al fotogramma dopo.
  Future<Future<void> Function()> removeWithUndo(int index, Track track) async {
    HapticFeedback.mediumImpact();
    final at = state[index].tracks.indexWhere((t) => t.id == track.id);
    state = [
      for (var i = 0; i < state.length; i++)
        i == index
            ? UserPlaylist(
                name: state[i].name,
                tracks: [
                  for (final t in state[i].tracks)
                    if (t.id != track.id) t,
                ],
                createdAt: state[i].createdAt,
              )
            : state[i],
    ];
    await removeTrack(index, track.id);
    return () async {
      await ref
          .read(storageServiceProvider)
          .insertTrackInPlaylist(index, track, at);
      state = _reload();
    };
  }

  List<UserPlaylist> _reload() {
    final raw = ref.read(storageServiceProvider).playlists;
    return raw.map((p) {
      final tracksRaw = (p['tracks'] as List?) ?? [];
      return UserPlaylist(
        name: p['name'] as String? ?? 'Playlist',
        tracks: tracksRaw
            .map((t) => Track.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList(),
        createdAt: p['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(p['createdAt'] as int)
            : null,
      );
    }).toList();
  }
}

final playlistsProvider =
    NotifierProvider<PlaylistsController, List<UserPlaylist>>(
      PlaylistsController.new,
    );

// ----------------------------------------------------------------------
// Radio / Smart Shuffle toggle
// ----------------------------------------------------------------------

/// When true, the player automatically fetches and appends related tracks
/// when the queue runs out (infinite radio mode).
class RadioController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final radioProvider = NotifierProvider<RadioController, bool>(
  RadioController.new,
);

// ----------------------------------------------------------------------
// Shell navigation
// ----------------------------------------------------------------------

/// Which bottom tab is selected.
///
/// Lives in a provider rather than in the shell's State so that any screen
/// can move the user to another tab — the Home search-history chips need to
/// land on "Cerca", and the macOS ⌘F shortcut has to reach it from outside
/// the widget tree entirely.
class NavTabController extends Notifier<int> {
  @override
  int build() => 0;

  static const int home = 0;
  static const int search = 1;
  static const int library = 2;
  static const int queue = 3;

  void select(int index) => state = index;
}

final navTabProvider = NotifierProvider<NavTabController, int>(
  NavTabController.new,
);

/// Focus node for the search field, so ⌘F (and the Home chips) can put the
/// caret straight into it.
final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'search');
  ref.onDispose(node.dispose);
  return node;
});
