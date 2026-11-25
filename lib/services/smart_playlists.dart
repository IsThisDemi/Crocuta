import 'package:flutter/material.dart';

import '../models/track.dart';

/// Le playlist che si fanno da sole, dai tuoi ascolti: come le "Made for
/// You" di Apple Music, ma calcolate qui, senza mandare niente a nessuno.
enum SmartKind {
  onRepeat(
    'On Repeat',
    'Your most played of the last 30 days',
    Icons.repeat_rounded,
    [Color(0xFFFF5E62), Color(0xFFFF9966)],
  ),
  recentlyLiked(
    'Recently Liked',
    'The songs you liked lately',
    Icons.favorite_rounded,
    [Color(0xFFEC4899), Color(0xFF8B5CF6)],
  ),
  lateNight(
    'Late Night',
    'What you play between 10 pm and 4 am',
    Icons.nightlight_round,
    [Color(0xFF1E3A8A), Color(0xFF7C3AED)],
  ),
  forgotten(
    'Forgotten Favorites',
    'Liked songs you haven\'t played in a while',
    Icons.history_rounded,
    [Color(0xFF0EA5A4), Color(0xFF22C55E)],
  ),
  discoverWeekly(
    'Discover Weekly',
    'New to you, picked from what you play most. Every Monday',
    Icons.explore_rounded,
    [Color(0xFF22D3EE), Color(0xFF6366F1)],
  ),
  dailyMix(
    'Daily Mix',
    'Songs you know and new ones, around the same sound',
    Icons.album_rounded,
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
  );

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;

  const SmartKind(this.title, this.subtitle, this.icon, this.colors);
}

class SmartPlaylist {
  final SmartKind kind;
  final List<Track> tracks;

  /// Per le playlist di cui ce n'e' piu' d'una dello stesso tipo — i
  /// Daily Mix —: nome, descrizione e colori propri.
  final String? _id;
  final String? _title;
  final String? _subtitle;
  final List<Color>? _colors;

  const SmartPlaylist(
    this.kind,
    this.tracks, {
    String? id,
    String? title,
    String? subtitle,
    List<Color>? colors,
  }) : _id = id,
       _title = title,
       _subtitle = subtitle,
       _colors = colors;

  String get id => _id ?? kind.name;
  String get title => _title ?? kind.title;
  String get subtitle => _subtitle ?? kind.subtitle;
  List<Color> get colors => _colors ?? kind.colors;
}

/// Un ascolto dal registro: quale brano, quando, per quanti secondi.
typedef Play = (String id, DateTime at, int seconds);

/// Quanto al massimo: una playlist da riascoltare, non un archivio.
const int smartLimit = 50;

/// I brani contati per ascolti, dal piu' ascoltato; a parita', chi e'
/// stato ascoltato piu' a lungo. Solo chi ha almeno [minPlays] ascolti:
/// uno solo non e' "in loop".
List<Track> _ranked(
  Iterable<Play> plays,
  Map<String, Track> tracks, {
  int minPlays = 2,
}) {
  final count = <String, int>{};
  final secs = <String, int>{};
  for (final (id, _, s) in plays) {
    count[id] = (count[id] ?? 0) + 1;
    secs[id] = (secs[id] ?? 0) + s;
  }
  final ids =
      [
        for (final e in count.entries)
          if (e.value >= minPlays && tracks.containsKey(e.key)) e.key,
      ]..sort((a, b) {
        final byCount = count[b]!.compareTo(count[a]!);
        return byCount != 0 ? byCount : secs[b]!.compareTo(secs[a]!);
      });
  return [for (final id in ids.take(smartLimit)) tracks[id]!];
}

/// I piu' ascoltati degli ultimi 30 giorni.
List<Track> onRepeat(
  List<Play> log,
  Map<String, Track> tracks, {
  required DateTime now,
}) {
  final since = now.subtract(const Duration(days: 30));
  return _ranked(log.where((p) => p.$2.isAfter(since)), tracks);
}

/// Quello che ascolti di notte, fra le 22 e le 4, in qualunque giorno.
List<Track> lateNight(List<Play> log, Map<String, Track> tracks) => _ranked(
  log.where((p) {
    final h = p.$2.hour;
    return h >= 22 || h < 4;
  }),
  tracks,
);

/// I preferiti aggiunti negli ultimi 30 giorni, dal piu' recente. Se sono
/// pochi, gli ultimi aggiunti comunque: la playlist non deve restare vuota
/// in un mese in cui non hai messo cuori.
List<Track> recentlyLiked(
  List<Track> favorites,
  Map<String, int> addedAt, {
  required DateTime now,
}) {
  final dated = [
    for (final t in favorites)
      if ((addedAt[t.id] ?? 0) > 0) t,
  ]..sort((a, b) => addedAt[b.id]!.compareTo(addedAt[a.id]!));
  final since = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
  final recent = [
    for (final t in dated)
      if (addedAt[t.id]! >= since) t,
  ];
  return (recent.length >= 10 ? recent : dated.take(25))
      .take(smartLimit)
      .toList();
}

/// I preferiti che non ascolti da piu' di due mesi, dal piu' dimenticato.
///
/// Conta l'ultimo ascolto; un preferito mai ascoltato qui conta dalla
/// data in cui l'hai aggiunto, perche' il registro degli ascolti e' piu'
/// giovane della libreria. Quelli aggiunti da poco non sono dimenticati.
List<Track> forgotten(
  List<Track> favorites,
  Map<String, DateTime> lastPlayed,
  Map<String, int> addedAt, {
  required DateTime now,
}) {
  final before = now.subtract(const Duration(days: 60));
  DateTime? last(Track t) {
    final played = lastPlayed[t.id];
    if (played != null) return played;
    final added = addedAt[t.id] ?? 0;
    return added > 0 ? DateTime.fromMillisecondsSinceEpoch(added) : null;
  }

  final old = [
    for (final t in favorites)
      if (last(t) case final d? when d.isBefore(before)) t,
  ]..sort((a, b) => last(a)!.compareTo(last(b)!));
  return old.take(smartLimit).toList();
}
