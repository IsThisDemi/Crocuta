import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers.dart';
import 'library_import.dart';
import 'spotify_api.dart';
import 'spotify_import.dart';
import 'storage_service.dart';

/// La libreria letta, da cui scegliere: di Spotify o di Apple Music.
class SpotifyLibrary {
  /// Chi ha fatto l'accesso a Spotify; null per Apple Music, che non ha
  /// un accesso.
  final SpotifyUser? user;

  /// Da dove viene, per chi non ha un accesso: "Read from the Music app".
  final String? note;
  final SpotifySource liked;
  final List<SpotifySource> playlists;
  final List<SpotifySource> albums;
  final List<SpotifySource> artists;

  const SpotifyLibrary({
    this.user,
    this.note,
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

/// Un import di libreria (Spotify, Apple Music): scegliere cosa, cercarlo
/// su YouTube Music, metterlo in Crocuta, riprendere dopo una pausa.
///
/// Il lavoro e' tutto di [SpotifyImporter]; chi estende dice solo come si
/// legge la libreria ([loadLibrary], [readTracks]) e dove si salva l'import
/// in corso ([savedJob], [saveJob]).
abstract class LibraryImportController extends Notifier<SpotifyImportView> {
  bool _cancel = false;

  StorageService get storage => ref.read(storageServiceProvider);

  /// L'import salvato, come JSON (vedi SpotifyImportState.encode).
  String? get savedJob;
  Future<void> saveJob(String? json);

  /// Legge cosa c'e' nella libreria, e la mette nella vista da scegliere.
  Future<void> loadLibrary();

  /// I brani di una raccolta, nel loro ordine.
  Future<List<SpotifyTrack>> readTracks(SpotifySource source);

  /// Il messaggio per un errore durante l'import.
  Future<String> describeError(Object error) async => error.toString();

  /// L'import si ferma dopo le ricerche in corso.
  void stopSoon() => _cancel = true;

  void showError(String message) => state = state.copyWith(error: message);

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
    await saveJob(job.encode());
    state = state.copyWith(job: job);
    await _run();
  }

  Future<void> resume() => _run();

  /// Ferma l'import dopo le ricerche in corso; resta salvato.
  void cancel() => stopSoon();

  /// Rimette in coda i non trovati e riparte.
  Future<void> retryMissing() async {
    final job = state.job;
    if (job == null || state.running) return;
    job.forgetMissing();
    await saveJob(job.encode());
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
    await saveJob(job.encode());
    state = state.copyWith(job: job);
  }

  /// Chiude l'import (finito o no) per poterne fare un altro.
  Future<void> discard() async {
    if (state.running) return;
    await saveJob(null);
    state = state.copyWith(job: null, progress: null, error: null);
    if (state.connected && state.library == null) unawaited(loadLibrary());
  }

  SpotifyImporter _importer() => SpotifyImporter(
    catalog: YouTubeSpotifyCatalog(ref.read(youtubeServiceProvider)),
    sink: _StorageSink(ref),
    readTracks: readTracks,
    save: (job) => saveJob(job.encode()),
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
    } catch (e) {
      state = state.copyWith(error: await describeError(e));
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
