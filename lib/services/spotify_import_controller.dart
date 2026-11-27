import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'library_import_controller.dart';
import 'spotify_api.dart';
import 'spotify_auth.dart';
import 'spotify_import.dart';
import 'storage_service.dart';

export 'library_import_controller.dart';

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

class SpotifyImportController extends LibraryImportController {
  http.Client? _client;
  SpotifySession? _session;

  StorageService get _storage => storage;

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

  Future<void> disconnect() async {
    stopSoon();
    await _storage.setSpotifyTokens(null);
    _session = null;
    state = state.copyWith(connected: false, library: null, selected: {});
  }

  /// Legge cosa c'e' nella libreria Spotify: i piaciuti (solo il numero),
  /// le playlist, i dischi, gli artisti.
  @override
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

  @override
  String? get savedJob => _storage.spotifyImport;

  @override
  Future<void> saveJob(String? json) => _storage.setSpotifyImport(json);

  @override
  Future<List<SpotifyTrack>> readTracks(SpotifySource s) async {
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
  }

  @override
  Future<String> describeError(Object error) async {
    if (error is SpotifyAuthException) {
      if (error.needsLogin) await disconnect();
      return error.message;
    }
    return error.toString();
  }
}
