import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers.dart';

/// I brani scaricati apposta, e quelli in corso di scaricamento.
///
/// Distinto dalla scorta del preloader: quella si riempie da sola mandando
/// avanti il brano successivo e si sfratta quando cresce troppo, questi li
/// scegli tu e restano finche' non li togli.
class DownloadsState {
  final List<Track> tracks;

  /// Avanzamento per id, da 0 a 1, solo per quelli in corso.
  final Map<String, double> inProgress;

  const DownloadsState({this.tracks = const [], this.inProgress = const {}});

  bool has(String id) => tracks.any((t) => t.id == id);
  bool isDownloading(String id) => inProgress.containsKey(id);

  DownloadsState copyWith({
    List<Track>? tracks,
    Map<String, double>? inProgress,
  }) => DownloadsState(
    tracks: tracks ?? this.tracks,
    inProgress: inProgress ?? this.inProgress,
  );
}

class DownloadsController extends Notifier<DownloadsState> {
  @override
  DownloadsState build() {
    final storage = ref.read(storageServiceProvider);
    // L'elenco viene riallineato a cio' che c'e' davvero su disco: un file
    // cancellato a mano, o perso in un aggiornamento, non deve restare
    // scritto in una lista che promette una cosa che non c'e' piu'.
    _reconcile();
    return DownloadsState(tracks: storage.downloads);
  }

  Future<void> _reconcile() async {
    // Tollerante di proposito: leggere il disco puo' fallire — nei test non
    // c'e' nemmeno un percorso applicativo — e un elenco che non si riesce
    // a riallineare non e' un motivo per far cadere la Libreria.
    try {
      final storage = ref.read(storageServiceProvider);
      final onDisk = await ref.read(songPreloaderProvider).downloadedIds();
      await storage.reconcileDownloads(
        onDisk,
        audioIdOf: ref.read(youtubeServiceProvider).knownAudioId,
      );
      final fresh = storage.downloads;
      if (fresh.length != state.tracks.length) {
        state = state.copyWith(tracks: fresh);
      }
    } catch (_) {}
  }

  /// Scarica un brano. Se e' gia' nella scorta lo sposta senza riscaricarlo.
  Future<bool> download(Track track) async {
    if (state.has(track.id) || state.isDownloading(track.id)) return true;
    state = state.copyWith(inProgress: {...state.inProgress, track.id: 0});
    try {
      // La canzone, non il videoclip: e' lo stesso file che il player
      // cerchera' prima di andare in rete.
      final audioId = await ref
          .read(youtubeServiceProvider)
          .audioIdFor(track.id);
      final result = await ref
          .read(songPreloaderProvider)
          .ensureDownloaded(
            audioId,
            permanent: true,
            onProgress: (p) {
              if (!state.isDownloading(track.id)) return;
              state = state.copyWith(
                inProgress: {...state.inProgress, track.id: p},
              );
            },
          );
      if (result == null) return false;
      await ref.read(storageServiceProvider).addDownload(track);
      // Il testo insieme al brano: scaricato vuol dire "anche senza rete",
      // e un brano offline col testo che non si apre e' offline a meta'.
      try {
        await lyricsFor(ref, title: track.title, artist: track.author);
      } catch (_) {}
      state = DownloadsState(
        tracks: ref.read(storageServiceProvider).downloads,
        inProgress: {...state.inProgress}..remove(track.id),
      );
      return true;
    } catch (_) {
      state = state.copyWith(
        inProgress: {...state.inProgress}..remove(track.id),
      );
      return false;
    }
  }

  Future<void> remove(String id) async {
    final preloader = ref.read(songPreloaderProvider);
    await preloader.removeDownload(id);
    final audioId = ref.read(youtubeServiceProvider).knownAudioId(id);
    if (audioId != id) await preloader.removeDownload(audioId);
    await ref.read(storageServiceProvider).removeDownload(id);
    state = state.copyWith(tracks: ref.read(storageServiceProvider).downloads);
  }
}
