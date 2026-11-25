import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

/// Un brano salvato che ha l'aria di essere un video e non la canzone.
///
/// Due indizi, uno basta: la copertina e' un fotogramma del video (gli
/// indirizzi `/vi/<id>/` sono quelli), oppure il titolo dice di esserlo,
/// "(Official Video)", "[Lyric Video]", "(Official Audio)".
bool looksLikeVideo(Track t) {
  final art = t.thumbnailUrl;
  if (art.contains('ytimg.com/vi/') || art.contains('img.youtube.com/vi/')) {
    return true;
  }
  return RegExp(
    r'[\(\[][^\)\]]*\b(official|video|visuali[sz]er|lyrics?|audio|clip)\b',
    caseSensitive: false,
  ).hasMatch(t.title);
}

/// Riveste da canzone i video salvati in libreria.
///
/// Quando il player incontra un video lo riconosce da se', ma solo nel
/// momento in cui lo suona: nei preferiti e nei recenti restavano titoli
/// come "Sfera Ebbasta - Lontano (Official Video)" su un fotogramma
/// tagliato a quadrato, fino al giorno in cui li avresti riascoltati.
///
/// Una passata all'avvio, in sottofondo e con calma: un brano alla volta,
/// con una pausa fra l'uno e l'altro, e al massimo [limit] per volta. Un
/// brano gia' controllato non costa niente, quindi dalla seconda volta in
/// poi restano solo quelli nuovi.
Future<int> tidyLibrary({
  required StorageService storage,
  required YouTubeService service,
  void Function()? onChanged,
  int limit = 30,
  Duration pause = const Duration(milliseconds: 400),
}) async {
  final seen = <String>{};
  final candidates = <Track>[
    for (final t in [
      ...storage.recentlyPlayed,
      ...storage.favorites,
      ...storage.downloads,
      for (final pl in storage.playlists)
        for (final e in (pl['tracks'] as List?) ?? const [])
          Track.fromJson(Map<String, dynamic>.from(e as Map)),
    ])
      if (looksLikeVideo(t) && seen.add(t.id)) t,
  ];

  final fixed = <Track>[];
  for (final t in candidates.take(limit)) {
    try {
      final song = await service.songVersionFor(t);
      if (song != null) fixed.add(song);
    } catch (_) {
      // Un brano che non risponde non ferma gli altri.
    }
    await Future<void>.delayed(pause);
  }

  if (fixed.isNotEmpty && await storage.refreshCachedTracks(fixed)) {
    onChanged?.call();
  }
  return fixed.length;
}

/// La passata, avviata una volta per sessione.
final libraryTidyProvider = FutureProvider<int>((ref) async {
  // Dopo l'avvio, non durante: la prima cosa da fare e' mostrare la Home e
  // riprendere la sessione, non interrogare YouTube su trenta brani.
  await Future<void>.delayed(const Duration(seconds: 8));
  return tidyLibrary(
    storage: ref.read(storageServiceProvider),
    service: ref.read(youtubeServiceProvider),
    onChanged: () {
      ref.invalidate(favoritesProvider);
      ref.invalidate(recentlyPlayedProvider);
      ref.invalidate(playlistsProvider);
    },
  );
});
