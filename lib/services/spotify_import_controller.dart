import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';
import '../providers.dart';
import 'library_import.dart';
import 'spotify_api.dart';
import 'spotify_auth.dart';
import 'spotify_import.dart';
import 'storage_service.dart';

/// La libreria Spotify letta, da cui scegliere.
class SpotifyLibrary {
  final SpotifyUser user;
  final SpotifySource liked;
  final List<SpotifySource> playlists;
  final List<SpotifySource> albums;
  final List<SpotifySource> artists;

  const SpotifyLibrary({
    required this.user,
    required this.liked,
    required this.playlists,
    required this.albums,
    required this.artists,
  });

  List<SpotifySource> get all => [liked, ...playlists, ...albums, ...artists];
}

/// Cosa mostra la pagina dell'import.
class SpotifyImportView {
  final String? clientId;
  final bool connected;
  final SpotifyLibrary? library;
  final bool loadingLibrary;
  final Set<String> selected;

  /// L'import in corso, fermo o finito. Lo stesso oggetto che l'importer
  /// aggiorna: la vista cambia a ogni passo per farlo ridisegnare.
  final SpotifyImportState? job;
  final bool running;
  final SpotifyImportProgress? progress;
  final String? error;

  const SpotifyImportView({
    this.clientId,
    this.connected = false,
    this.library,
    this.loadingLibrary = false,
    this.selected = const {},
    this.job,
    this.running = false,
    this.progress,
    this.error,
  });

  static const _keep = Object();

  SpotifyImportView copyWith({
    Object? clientId = _keep,
    bool? connected,
    Object? library = _keep,
    bool? loadingLibrary,
    Set<String>? selected,
    Object? job = _keep,
    bool? running,
    Object? progress = _keep,
    Object? error = _keep,
  }) => SpotifyImportView(
    clientId: identical(clientId, _keep) ? this.clientId : clientId as String?,
    connected: connected ?? this.connected,
    library: identical(library, _keep)
        ? this.library
        : library as SpotifyLibrary?,
    loadingLibrary: loadingLibrary ?? this.loadingLibrary,
    selected: selected ?? this.selected,
    job: identical(job, _keep) ? this.job : job as SpotifyImportState?,
    running: running ?? this.running,
    progress: identical(progress, _keep)
        ? this.progress
        : progress as SpotifyImportProgress?,
    error: identical(error, _keep) ? this.error : error as String?,
  );
}

/// Un Client ID di Spotify: 32 cifre esadecimali.
bool isSpotifyClientId(String s) =>
    RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(s.trim());

/// Un accesso in corso: il verifier resta qui finche' Spotify non rimanda
/// il codice.
typedef SpotifyLogin = ({Uri url, String verifier, String state});

/// L'import da Spotify, vivo finche' vive l'app: si puo' lasciare la
/// pagina e l'import continua.
final spotifyImportProvider =
    NotifierProvider<SpotifyImportController, SpotifyImportView>(
      SpotifyImportController.new,
    );

class SpotifyImportController extends Notifier<SpotifyImportView> {
  http.Client? _client;
  SpotifySession? _session;
  bool _cancel = false;

  StorageService get _storage => ref.read(storageServiceProvider);

  http.Client get _http => _client ??= http.Client();

  @override
  SpotifyImportView build() {
    ref.onDispose(() => _client?.close());
    final storage = _storage;
    return SpotifyImportView(
      clientId: storage.spotifyClientId,
      connected: _tokens() != null,
      job: SpotifyImportState.decode(storage.spotifyImport),
    );
  }

  SpotifyTokens? _tokens() {
    final raw = _storage.spotifyTokens;
    if (raw == null) return null;
    try {
      return SpotifyTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  SpotifyAuth _auth(String clientId) =>
      SpotifyAuth(client: _http, clientId: clientId);

  SpotifyApi? _api() {
    final clientId = state.clientId;
    final tokens = _tokens();
    if (clientId == null || tokens == null) return null;
    final session = _session ??= SpotifySession(
      auth: _auth(clientId),
      tokens: tokens,
      onTokens: (t) => _storage.setSpotifyTokens(jsonEncode(t.toJson())),
    );
    return SpotifyApi(client: _http, accessToken: session.accessToken);
  }

  Future<void> setClientId(String id) async {
    final clean = id.trim();
    if (clean == state.clientId) return;
    await _storage.setSpotifyClientId(clean);
    // Un'altra app Spotify: i token della vecchia non valgono.
    await _storage.setSpotifyTokens(null);
    _session = null;
    state = state.copyWith(clientId: clean, connected: false, library: null);
  }

  /// Prepara la pagina di consenso.
  SpotifyLogin startLogin() {
    final verifier = pkceVerifier();
    final st = randomState();
    return (
      url: spotifyAuthorizeUrl(
        clientId: state.clientId!,
        challenge: pkceChallenge(verifier),
        state: st,
      ),
      verifier: verifier,
      state: st,
    );
  }

  /// Scambia il codice coi token, poi legge la libreria.
  Future<void> finishLogin(String code, String verifier) async {
    state = state.copyWith(error: null, loadingLibrary: true);
    try {
      final tokens = await _auth(state.clientId!).exchangeCode(code, verifier);
      await _storage.setSpotifyTokens(jsonEncode(tokens.toJson()));
      _session = null;
      state = state.copyWith(connected: true);
    } catch (e) {
      state = state.copyWith(error: e.toString(), loadingLibrary: false);
      return;
    }
    await loadLibrary();
  }

  void showError(String message) => state = state.copyWith(error: message);

  Future<void> disconnect() async {
    _cancel = true;
    await _storage.setSpotifyTokens(null);
    _session = null;
    state = state.copyWith(connected: false, library: null, selected: {});
  }

  /// Legge cosa c'e' nella libreria Spotify: i piaciuti (solo il numero),
  /// le playlist, i dischi, gli artisti.
  Future<void> loadLibrary() async {
    final api = _api();
    if (api == null) return;
    state = state.copyWith(loadingLibrary: true, error: null);
    try {
      final user = await api.me();
      final liked = await api.likedCount();
      final playlists = await api.playlists();
      final albums = await api.savedAlbums();
      final artists = await api.followedArtists();
      final library = SpotifyLibrary(
        user: user,
        liked: SpotifySource.liked(liked),
        playlists: [
          for (final p in playlists) SpotifySource.playlist(p, user.id),
        ],
        albums: [for (final a in albums) SpotifySource.album(a)],
        artists: [for (final a in artists) SpotifySource.artist(a)],
      );
      state = state.copyWith(
        library: library,
        loadingLibrary: false,
        // Di serie tutto quello che si puo' leggere: le playlist di altri
        // si possono scegliere, ma Spotify probabilmente non le dara'.
        selected: {
          for (final s in library.all)
            if (!s.restricted &&
                (s.kind != SpotifySourceKind.liked || liked > 0))
              s.key,
        },
      );
    } on SpotifyAuthException catch (e) {
      if (e.needsLogin) await disconnect();
      state = state.copyWith(error: e.message, loadingLibrary: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), loadingLibrary: false);
    }
  }

  void toggle(String key) {
    final next = {...state.selected};
    if (!next.remove(key)) next.add(key);
    state = state.copyWith(selected: next);
  }

  /// Sceglie o toglie tutto, o tutto di un tipo.
  void selectAll(bool on, {SpotifySourceKind? kind}) {
    final library = state.library;
    if (library == null) return;
    final keys = [
      for (final s in library.all)
        if (kind == null || s.kind == kind) s.key,
    ];
    final next = {...state.selected};
    on ? next.addAll(keys) : next.removeAll(keys);
    state = state.copyWith(selected: next);
  }

  /// Comincia un import con le cose scelte.
  Future<void> start() async {
    final library = state.library;
    if (library == null || state.running) return;
    final job = SpotifyImportState(
      sources: [
        for (final s in library.all)
          if (state.selected.contains(s.key)) s,
      ],
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (job.sources.isEmpty) return;
    await _storage.setSpotifyImport(job.encode());
    state = state.copyWith(job: job);
    await _run();
  }

  Future<void> resume() => _run();

  /// Ferma l'import dopo le ricerche in corso; resta salvato.
  void cancel() => _cancel = true;

  /// Rimette in coda i non trovati e riparte.
  Future<void> retryMissing() async {
    final job = state.job;
    if (job == null || state.running) return;
    job.forgetMissing();
    await _storage.setSpotifyImport(job.encode());
    await _run();
  }

  /// Un brano scelto a mano per uno che la ricerca non aveva trovato:
  /// entra subito nei piaciuti e nelle playlist in cui stava.
  Future<void> pick(String key, Track track) async {
    final job = state.job;
    if (job == null || state.running) return;
    job.songs[key] = track;
    job.manual.add(key);
    await _importer().apply(job);
    await _storage.setSpotifyImport(job.encode());
    state = state.copyWith(job: job);
  }

  /// Chiude l'import (finito o no) per poterne fare un altro.
  Future<void> discard() async {
    if (state.running) return;
    await _storage.setSpotifyImport(null);
    state = state.copyWith(job: null, progress: null, error: null);
    if (state.connected && state.library == null) unawaited(loadLibrary());
  }

  SpotifyImporter _importer() => SpotifyImporter(
    catalog: YouTubeSpotifyCatalog(ref.read(youtubeServiceProvider)),
    sink: _StorageSink(ref),
    readTracks: (s) async {
      final api = _api();
      if (api == null) {
        throw const SpotifyAuthException(
          'Connect to Spotify again to read the rest of your library.',
          needsLogin: true,
        );
      }
      return s.kind == SpotifySourceKind.liked
          ? api.likedSongs()
          : api.playlistTracks(s.id);
    },
    save: (job) => _storage.setSpotifyImport(job.encode()),
  );

  Future<void> _run() async {
    final job = state.job;
    if (job == null || state.running) return;
    _cancel = false;
    state = state.copyWith(running: true, error: null, progress: null);
    try {
      await _importer().run(
        job,
        onProgress: (p) => state = state.copyWith(progress: p, job: job),
        cancelled: () => _cancel,
      );
    } on SpotifyAuthException catch (e) {
      if (e.needsLogin) await disconnect();
      state = state.copyWith(error: e.message);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(running: false, job: job);
    }
  }
}

/// Dove l'import scrive: lo storage, e i provider da ricaricare perche'
/// le pagine della libreria lo vedano subito.
class _StorageSink implements SpotifyLibrarySink {
  final Ref ref;

  _StorageSink(this.ref);

  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  Future<void> addLiked(List<Track> newestFirst) async {
    final storage = _storage;
    final plan = planLibraryImport(
      existing: storage.favorites,
      existingAddedAt: storage.marks('fav'),
      incoming: newestFirst,
      now: DateTime.now().millisecondsSinceEpoch,
    );
    if (plan.tracks.isNotEmpty || plan.datedExisting.isNotEmpty) {
      await storage.importFavorites(
        plan.tracks,
        plan.addedAt,
        dates: plan.datedExisting,
      );
    }
    ref.invalidate(favoritesProvider);
  }

  @override
  Future<String> createPlaylist(String name, List<Track> tracks) async {
    final storage = _storage;
    final list = storage.playlists;
    final ids = {for (final p in list) p['id']};
    var now = DateTime.now().millisecondsSinceEpoch;
    // Lo stesso schema di StorageService.createPlaylist, ma con i brani
    // dentro in una scrittura sola.
    String idAt(int t) =>
        'pl_${t}_${name.hashCode.toUnsigned(16).toRadixString(16)}';
    while (ids.contains(idAt(now))) {
      now++;
    }
    final id = idAt(now);
    list.add({
      'id': id,
      'name': name,
      'tracks': [for (final t in tracks) t.toJson()],
      'createdAt': now,
    });
    await storage.savePlaylists(list);
    await storage.mark('pl', id);
    ref.invalidate(playlistsProvider);
    return id;
  }

  @override
  Future<bool> addToPlaylist(
    String id,
    List<Track> ordered,
    Set<String> fresh,
  ) async {
    final storage = _storage;
    final index = storage.playlists.indexWhere((p) => p['id'] == id);
    if (index < 0) return false;
    final merged = mergeIntoPlaylist(
      storage.getPlaylistTracks(index),
      ordered,
      fresh,
    );
    await storage.setPlaylistTracks(index, merged);
    ref.invalidate(playlistsProvider);
    return true;
  }

  @override
  Future<void> follow(ArtistMatch artist) async {
    final storage = _storage;
    if (storage.isFollowing(artist.browseId)) return;
    // Come il tasto "Segui": le uscite di adesso si segnano come viste.
    await storage.follow(
      browseId: artist.browseId,
      name: artist.name,
      thumbnailUrl: artist.thumbnailUrl,
    );
    await storage.setSeenReleases(artist.browseId, artist.releases.toSet());
    ref.invalidate(followsProvider);
  }
}
