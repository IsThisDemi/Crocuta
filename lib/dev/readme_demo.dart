import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import 'readme_shots.dart';

/// La libreria finta delle foto del README.
///
/// Le foto non devono mostrare la libreria di chi le scatta: ricerche,
/// ascolti, classifiche e nome del computer sono fatti suoi, e il README
/// e' pubblico. Con `README_SHOTS` l'app apre quindi i suoi box in una
/// cartella a parte, svuotata a ogni avvio, e la riempie con brani noti
/// cercati su YouTube Music come farebbe chiunque. La libreria vera resta
/// dov'e', mai aperta.
Future<void> openReadmeDemoStorage(StorageService storage) async {
  final dir = Directory('${Directory.systemTemp.path}/readme_demo');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  await storage.init(path: dir.path);
  await _seed(storage);
}

/// (ricerca, artista atteso, ascolti in tutto). Il primo e' il brano delle
/// foto, gli altri girano intorno.
const _songs = <(String, String, int)>[
  ('$readmeShotsTrack $readmeShotsArtist', readmeShotsArtist, 96),
  ('Espresso Sabrina Carpenter', 'Sabrina Carpenter', 184),
  ('Denial Is a River Doechii', 'Doechii', 171),
  ('BIRDS OF A FEATHER Billie Eilish', 'Billie Eilish', 158),
  ('Good Luck, Babe! Chappell Roan', 'Chappell Roan', 142),
  ('Not Like Us Kendrick Lamar', 'Kendrick Lamar', 133),
  ('360 Charli xcx', 'Charli xcx', 121),
  ('Saturn SZA', 'SZA', 117),
  ('Get Lucky Daft Punk', 'Daft Punk', 104),
  ('Houdini Dua Lipa', 'Dua Lipa', 92),
  ('Water Tyla', 'Tyla', 88),
  ('DESPECHÁ ROSALÍA', 'ROSALÍA', 81),
  ('EARFQUAKE Tyler, The Creator', 'Tyler, The Creator', 77),
  ('Tití Me Preguntó Bad Bunny', 'Bad Bunny', 70),
  ('Pink + White Frank Ocean', 'Frank Ocean', 64),
  ('Die With A Smile Lady Gaga Bruno Mars', 'Lady Gaga', 58),
  ('Paint The Town Red Doja Cat', 'Doja Cat', 51),
  ('TEXAS HOLD \'EM Beyoncé', 'Beyoncé', 45),
  ('Anxiety Doechii', 'Doechii', 41),
  ('Von dutch Charli xcx', 'Charli xcx', 37),
];

const _followed = [
  'GloRilla',
  'Doechii',
  'Charli xcx',
  'Sabrina Carpenter',
  'SZA',
  'Tyler, The Creator',
];

const _searches = ['daft punk', 'tyla', 'chappell roan', 'jazz', 'rosalía'];

Future<void> _seed(StorageService storage) async {
  final yt = YouTubeService(onDurationResolved: storage.saveDuration);
  var tracks = <(Track, int)>[];
  try {
    for (final (query, artist, plays) in _songs) {
      try {
        final found = (await yt.search(query)).songs;
        final want = artist.toLowerCase();
        final hit =
            found
                .where((t) => t.author.toLowerCase().contains(want))
                .firstOrNull ??
            found.firstOrNull;
        if (hit != null) tracks.add((hit, plays));
      } catch (e) {
        debugPrint('readme demo: "$query" non trovato: $e');
      }
    }
    for (final name in _followed) {
      try {
        final a = (await yt.search(name)).artists.firstOrNull;
        if (a != null) {
          await storage.follow(
            browseId: a.browseId,
            name: a.title,
            thumbnailUrl: a.thumbnailUrl,
          );
        }
      } catch (e) {
        debugPrint('readme demo: artista "$name" non trovato: $e');
      }
    }
    // La ricerca non porta le durate: senza, la barra del player resta a
    // "--:--" e ogni ascolto conta tre minuti tondi.
    final all = [for (final (t, _) in tracks) t];
    await yt.enrichDurations(all);
    await yt.enrichDurations(all);
    final known = storage.durationCache;
    tracks = [
      for (final (t, plays) in tracks)
        (
          t.duration == null && known[t.id] != null
              ? t.copyWith(duration: known[t.id])
              : t,
          plays,
        ),
    ];
  } finally {
    yt.dispose();
  }

  // Preferiti: quasi tutti. Recenti: in un ordine che non sia la
  // classifica, col brano delle foto davanti.
  for (final (t, _) in tracks.skip(1)) {
    await storage.addFavorite(t);
  }
  final recent = [
    for (final i in [5, 3, 1, 10, 7, 12, 2, 16, 8, 0])
      if (i < tracks.length) tracks[i].$1,
  ];
  for (final t in recent.reversed) {
    await storage.addRecentlyPlayed(t);
  }

  // Un anno d'ascolti, sempre gli stessi: il seme e' fisso.
  final rnd = Random(7);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final log = <String, List<List<int>>>{};
  final stats = <String, dynamic>{};
  for (final (t, plays) in tracks) {
    final secs = t.duration?.inSeconds ?? 180;
    final when = [
      for (var i = 0; i < plays; i++) now - rnd.nextInt(360 * 86400),
    ]..sort();
    log[t.id] = [
      for (final w in when) [w, secs],
    ];
    stats[t.id] = {
      'count': plays,
      'lastPlayed': when.last * 1000,
      'totalSeconds': plays * secs,
    };
  }
  await storage.replacePlayLog(log);
  await storage.replaceAllPlayStats(stats);
  await storage.addStatTracks({for (final (t, _) in tracks) t.id: t.toJson()});

  for (final q in _searches.reversed) {
    await storage.addSearchQuery(q);
  }
  for (final (name, picks) in [
    ('Late Drive', [7, 14, 3, 11]),
    ('Gym', [0, 5, 2, 18, 6]),
  ]) {
    await storage.createPlaylist(name);
    final index = storage.playlists.length - 1;
    for (final i in picks) {
      if (i < tracks.length) {
        await storage.addTrackToPlaylist(index, tracks[i].$1);
      }
    }
  }

  // Il brano delle foto come sessione ripristinata, con una coda dietro
  // e AutoMix e la coda infinita accesi, come li usa chi ascolta davvero.
  if (tracks.isNotEmpty) {
    final star = tracks.first.$1;
    await storage.saveQueue([
      star,
      for (final i in [4, 8, 2, 11, 6, 15, 9, 13, 1, 17])
        if (i < tracks.length) tracks[i].$1,
    ]);
    await storage.savePlaybackSession(
      index: 0,
      position: const Duration(seconds: 62),
      duration: star.duration ?? Duration.zero,
      shuffle: false,
      repeat: 'off',
      crossfade: Duration.zero,
      radio: true,
      automix: true,
    );
  }

  // Il nome del computer non deve finire nelle foto, e Connect non deve
  // trovare i dispositivi veri sulla stessa rete.
  await storage.setConnectName('MacBook Pro');
  await storage.setConnectEnabled(false);
  debugPrint(
    'readme demo: ${tracks.length} brani, ${_followed.length} artisti',
  );
}
