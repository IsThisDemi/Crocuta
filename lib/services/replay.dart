import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artist.dart';
import '../models/artist_names.dart';
import '../models/track.dart';
import '../providers.dart';

/// Di quale periodo fare il riepilogo.
enum ReplayPeriod {
  week('Week', 'this week'),
  month('Month', 'this month'),
  year('Year', 'this year'),
  allTime('All Time', 'yet');

  /// Corta, per stare in quattro in un selettore largo un telefono.
  final String label;

  /// Per le frasi: "Nothing played this week".
  final String phrase;
  const ReplayPeriod(this.label, this.phrase);

  /// Da quando conta. Nullo per "sempre".
  ///
  /// La settimana comincia lunedi', come nel calendario italiano, e tutto
  /// comincia a mezzanotte: "questo mese" il primo del mese alle 9 deve
  /// gia' contenere l'ascolto delle 8.
  DateTime? start(DateTime now) => switch (this) {
    week => DateTime(now.year, now.month, now.day - (now.weekday - 1)),
    month => DateTime(now.year, now.month),
    year => DateTime(now.year),
    allTime => null,
  };
}

/// Un brano in classifica.
class ReplayTrack {
  final Track track;
  final int plays;
  final int seconds;
  const ReplayTrack(this.track, this.plays, this.seconds);
}

/// Un artista in classifica.
class ReplayArtist {
  final String name;
  final String? artistId;
  final String artwork;
  final int plays;
  final int seconds;
  const ReplayArtist({
    required this.name,
    required this.artwork,
    required this.plays,
    required this.seconds,
    this.artistId,
  });
}

/// Un disco in classifica.
class ReplayAlbum {
  final AlbumCard album;
  final int plays;
  const ReplayAlbum(this.album, this.plays);
}

/// Il riepilogo di un periodo.
class ReplaySummary {
  final int plays;
  final int seconds;
  final int songs;

  /// Quanti artisti diversi, tutti: [artists] e' solo la classifica, i
  /// primi dodici. La scheda dei minuti contava quella, e diceva "12
  /// artisti" a chiunque ne avesse ascoltati di piu'.
  final int artistCount;
  final List<ReplayTrack> tracks;
  final List<ReplayArtist> artists;
  final List<ReplayAlbum> albums;

  /// Da quando si registrano i singoli ascolti. I periodi prima di allora
  /// non si possono ricostruire, e la pagina lo deve dire invece di
  /// mostrare un mese mezzo vuoto come se fosse vero.
  final DateTime? countingSince;

  const ReplaySummary({
    this.plays = 0,
    this.seconds = 0,
    this.songs = 0,
    this.artistCount = 0,
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.countingSince,
  });
}

/// Il riepilogo di [period], come Replay di Apple.
///
/// "Sempre" legge i totali, che contano dal primo giorno dell'app; gli
/// altri periodi il registro dei singoli ascolti, che esiste da quando c'e'
/// questa pagina. Le classifiche sono per tempo ascoltato, come in Replay:
/// dieci ascolti saltati dopo trenta secondi non valgono un disco intero.
ReplaySummary buildReplay({
  required ReplayPeriod period,
  required DateTime now,
  required Map<String, TrackStats> allTime,
  required List<(String, DateTime, int)> log,
  required Map<String, Track> tracks,
  Map<String, String> artistPhotos = const {},
}) {
  final plays = <String, int>{};
  final seconds = <String, int>{};
  final since = period.start(now);
  if (since == null) {
    // I totali di sempre possono essere gonfiati: una versione vecchia
    // dell'app, su un altro dispositivo, contava anche il tempo in pausa,
    // e la sincronizzazione tiene il valore piu' alto. Hope risultava 29
    // ascolti per 68 minuti, il tetto massimo, quando il registro ne aveva
    // 19 per 16 minuti. Dove c'e' il registro vale lui; gli ascolti piu'
    // vecchi del registro si stimano con la durata media che quel brano ha
    // nel registro, e senza registro al massimo la durata del brano.
    final logPlays = <String, int>{};
    final logSecs = <String, int>{};
    for (final (id, _, secs) in log) {
      logPlays[id] = (logPlays[id] ?? 0) + 1;
      logSecs[id] = (logSecs[id] ?? 0) + secs;
    }
    for (final e in allTime.entries) {
      final id = e.key;
      final count = e.value.playCount;
      final total = e.value.totalSeconds;
      final lp = logPlays[id] ?? 0;
      final ls = logSecs[id] ?? 0;
      final older = math.max(0, count - lp);
      final duration = tracks[id]?.duration?.inSeconds;
      final perPlay = lp > 0
          ? ls / lp
          : count == 0
          ? 0.0
          : math.min(total / count, (duration ?? total / count).toDouble());
      plays[id] = math.max(count, lp);
      seconds[id] = math.min(total, ls + (older * perPlay).round());
    }
  } else {
    for (final (id, at, secs) in log) {
      if (at.isBefore(since)) continue;
      plays[id] = (plays[id] ?? 0) + 1;
      seconds[id] = (seconds[id] ?? 0) + secs;
    }
  }

  int byTime(int sa, int pa, int sb, int pb) =>
      sb != sa ? sb.compareTo(sa) : pb.compareTo(pa);

  final ranked = <ReplayTrack>[
    for (final id in plays.keys)
      if (tracks[id] case final t?) ReplayTrack(t, plays[id]!, seconds[id]!),
  ]..sort((a, b) => byTime(a.seconds, a.plays, b.seconds, b.plays));

  final aPlays = <String, int>{};
  final aSecs = <String, int>{};
  final aId = <String, String>{};
  final aArt = <String, String>{};
  final alPlays = <String, int>{};
  final alCard = <String, AlbumCard>{};
  // Dal piu' ascoltato: cosi' la copertina di ripiego di un artista e'
  // quella del suo brano piu' ascoltato, non di uno qualsiasi.
  for (final r in ranked) {
    final t = r.track;
    final name = ArtistNames.splitArtists(t.author).firstOrNull ?? t.author;
    aPlays[name] = (aPlays[name] ?? 0) + r.plays;
    aSecs[name] = (aSecs[name] ?? 0) + r.seconds;
    if (t.artistId != null) aId.putIfAbsent(name, () => t.artistId!);
    if (t.thumbnailUrl.isNotEmpty) aArt.putIfAbsent(name, () => t.thumbnailUrl);
    if (t.albumId case final album?) {
      alPlays[album] = (alPlays[album] ?? 0) + r.plays;
      alCard.putIfAbsent(
        album,
        () => AlbumCard(
          browseId: album,
          title: t.albumName ?? t.title,
          subtitle: name,
          thumbnailUrl: t.thumbnailUrl,
        ),
      );
    }
  }

  final artists = [
    for (final name in aPlays.keys)
      ReplayArtist(
        name: name,
        artistId: aId[name],
        artwork: artistPhotos[name] ?? aArt[name] ?? '',
        plays: aPlays[name]!,
        seconds: aSecs[name]!,
      ),
  ]..sort((a, b) => byTime(a.seconds, a.plays, b.seconds, b.plays));

  final albums = [
    for (final id in alPlays.keys) ReplayAlbum(alCard[id]!, alPlays[id]!),
  ]..sort((a, b) => b.plays.compareTo(a.plays));

  return ReplaySummary(
    plays: plays.values.fold(0, (a, b) => a + b),
    seconds: seconds.values.fold(0, (a, b) => a + b),
    songs: plays.values.where((p) => p > 0).length,
    tracks: ranked.take(25).toList(),
    artistCount: artists.length,
    artists: artists.take(12).toList(),
    albums: albums.take(12).toList(),
    countingSince: log.isEmpty
        ? null
        : log.map((e) => e.$2).reduce((a, b) => a.isBefore(b) ? a : b),
  );
}

final replayProvider = Provider.family<ReplaySummary, ReplayPeriod>((
  ref,
  period,
) {
  // statsProvider cambia a ogni ascolto registrato, e il registro viene
  // scritto prima: guardare lui basta a tenere aggiornata la pagina.
  final allTime = ref.watch(statsProvider);
  final storage = ref.read(storageServiceProvider);
  // I brani piu' freschi per ultimi, perche' vincano: recenti e preferiti
  // possono essere stati ripuliti (video rivestiti da canzone) dopo
  // l'ultimo ascolto.
  final tracks = {
    ...storage.statTracks,
    for (final t in ref.watch(favoritesProvider)) t.id: t,
    for (final t in ref.watch(recentlyPlayedProvider)) t.id: t,
  };
  return buildReplay(
    period: period,
    now: DateTime.now(),
    allTime: allTime,
    log: storage.playLog,
    tracks: tracks,
    artistPhotos: {
      for (final a in ref.watch(followsProvider))
        if (a.thumbnailUrl != null) a.name: a.thumbnailUrl!,
    },
  );
});
