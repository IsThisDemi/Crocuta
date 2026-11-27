import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'apple_music_library.dart';
import 'library_import_controller.dart';
import 'spotify_api.dart';
import 'spotify_import.dart';

export 'library_import_controller.dart';

/// L'import da Apple Music: lo stesso di Spotify (vedi
/// [LibraryImportController]), cambia solo da dove si legge.
///
/// Sul Mac e sull'iPhone dalla libreria dell'app Musica, col permesso del
/// sistema; ovunque da un file esportato da Musica o da iTunes ("Esporta
/// libreria…"). Niente accesso e niente server: la libreria letta resta in
/// memoria finche' serve.
final appleMusicImportProvider =
    NotifierProvider<AppleMusicImportController, SpotifyImportView>(
      AppleMusicImportController.new,
    );

class AppleMusicImportController extends LibraryImportController {
  AppleMusicLibrary? _library;

  @override
  SpotifyImportView build() =>
      SpotifyImportView(job: SpotifyImportState.decode(savedJob));

  @override
  String? get savedJob => storage.appleMusicImport;

  @override
  Future<void> saveJob(String? json) => storage.setAppleMusicImport(json);

  /// Legge la libreria dell'app Musica di questo dispositivo.
  @override
  Future<void> loadLibrary() async {
    if (!AppleMusicReader.isSupported) return;
    state = state.copyWith(loadingLibrary: true, error: null);
    try {
      _use(await AppleMusicReader.read());
    } catch (e) {
      state = state.copyWith(error: e.toString(), loadingLibrary: false);
    }
  }

  /// Legge un file esportato. [read] lo legge dal disco: qui solo il
  /// testo, cosi' i test passano una stringa.
  Future<void> loadFile(String name, Future<String> Function() read) async {
    state = state.copyWith(loadingLibrary: true, error: null);
    try {
      final text = await read();
      // Una libreria di anni sono decine di MB di XML: fuori dal thread
      // dell'interfaccia.
      final library = await compute(
        (String t) => parseAppleMusicFile(t, name: name),
        text,
      );
      _use(library);
    } catch (e) {
      state = state.copyWith(error: e.toString(), loadingLibrary: false);
    }
  }

  void _use(AppleMusicLibrary library) {
    if (library.isEmpty) {
      state = state.copyWith(
        error: 'There are no songs or playlists in ${library.origin}.',
        loadingLibrary: false,
      );
      return;
    }
    _library = library;
    final view = libraryViewOf(library);
    state = state.copyWith(
      connected: true,
      library: view,
      loadingLibrary: false,
      selected: {
        for (final s in view.all)
          if (s.count > 0) s.key,
      },
    );
  }

  /// Si torna alla scelta di cosa leggere.
  Future<void> disconnect() async {
    stopSoon();
    _library = null;
    state = state.copyWith(connected: false, library: null, selected: {});
  }

  @override
  Future<List<SpotifyTrack>> readTracks(SpotifySource source) async {
    var library = _library;
    // Un import ripreso dopo aver chiuso Crocuta: la libreria non c'e'
    // piu' in memoria. Sul Mac e sull'iPhone si rilegge dall'app Musica —
    // anche se era venuta da un file: gli id dei brani sono gli stessi
    // dell'XML di Musica. Altrove il file va riaperto.
    if (library == null && AppleMusicReader.isSupported) {
      library = _library = await AppleMusicReader.read();
    }
    if (library == null) {
      throw const AppleMusicFormatException(
        'Open your library again to read the rest of it.',
      );
    }
    if (source.kind == SpotifySourceKind.liked) return library.songs;
    for (final p in library.playlists) {
      if (p.id == source.id) return p.tracks;
    }
    // Una playlist che non c'e' piu': vuota, e l'import va avanti.
    return const [];
  }
}

/// La libreria da scegliere: i brani (che diventano i preferiti, come i
/// piaciuti di Spotify) e le playlist.
SpotifyLibrary libraryViewOf(AppleMusicLibrary library) => SpotifyLibrary(
  note: 'Read from ${library.origin}.',
  liked: SpotifySource(
    kind: SpotifySourceKind.liked,
    id: 'liked',
    name: 'Library Songs',
    count: library.songs.length,
  ),
  playlists: [
    for (final p in library.playlists)
      SpotifySource(
        kind: SpotifySourceKind.playlist,
        id: p.id,
        name: p.name,
        count: p.tracks.length,
      ),
  ],
  albums: const [],
  artists: const [],
);
