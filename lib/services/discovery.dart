import 'package:flutter/material.dart';

import '../models/artist_names.dart';
import '../models/track.dart';

/// La scoperta di musica nuova: Discover Weekly e i Daily Mix.
///
/// Tutto dai tuoi ascolti e dalle radio di YouTube, calcolato qui: le
/// radio dei brani che ascolti di piu' dicono cosa c'e' vicino ai tuoi
/// gusti, e i tuoi ascolti dicono cosa conosci gia'.

/// L'artista principale di un brano: il primo dei nomi.
String mainArtist(Track t) =>
    ArtistNames.splitArtists(t.author).firstOrNull ?? t.author;

/// Discover Weekly: i brani che non hai mai sentito, dalle radio dei tuoi
/// piu' ascoltati.
///
/// Conta quante radio propongono lo stesso brano: comparire vicino a due o
/// tre brani che ami e' un segnale piu' forte che comparire vicino a uno.
/// A parita', vale la posizione: YouTube mette in cima i piu' affini. Al
/// massimo due brani per artista, perche' una playlist di scoperta fatta
/// di un solo artista non scopre niente.
List<Track> pickDiscover(
  List<List<Track>> radios,
  Set<String> heard, {
  int limit = 30,
}) {
  final count = <String, int>{};
  final bestRank = <String, int>{};
  final byId = <String, Track>{};
  for (final radio in radios) {
    final seen = <String>{};
    for (var i = 0; i < radio.length; i++) {
      final t = radio[i];
      if (heard.contains(t.id) || !seen.add(t.id)) continue;
      byId[t.id] = t;
      count[t.id] = (count[t.id] ?? 0) + 1;
      final r = bestRank[t.id];
      if (r == null || i < r) bestRank[t.id] = i;
    }
  }
  final ids = byId.keys.toList()
    ..sort((a, b) {
      final c = count[b]!.compareTo(count[a]!);
      return c != 0 ? c : bestRank[a]!.compareTo(bestRank[b]!);
    });
  final perArtist = <String, int>{};
  final out = <Track>[];
  for (final id in ids) {
    final t = byId[id]!;
    final artist = mainArtist(t).toLowerCase();
    if ((perArtist[artist] ?? 0) >= 2) continue;
    perArtist[artist] = (perArtist[artist] ?? 0) + 1;
    out.add(t);
    if (out.length >= limit) break;
  }
  return out;
}

/// Un Daily Mix: i brani che conosci attorno a un artista che ascolti, e
/// quelli nuovi che gli stanno vicino, alternati. [seeds] sono i tuoi brani
/// di quell'artista; [radios] le loro radio.
List<Track> buildMix({
  required List<Track> seeds,
  required List<List<Track>> radios,
  required Set<String> heard,
  int known = 12,
  int fresh = 13,
}) {
  final knownOut = <Track>[];
  final freshOut = <Track>[];
  final seen = <String>{};
  for (final t in seeds) {
    if (seen.add(t.id) && knownOut.length < known) knownOut.add(t);
  }
  // Le radio lette a righe, un brano da ciascuna per volta: cosi' il mix
  // attinge a tutte, non solo alla prima.
  final longest = radios.fold(0, (n, r) => r.length > n ? r.length : n);
  for (var i = 0; i < longest; i++) {
    for (final r in radios) {
      if (i >= r.length) continue;
      final t = r[i];
      if (!seen.add(t.id)) continue;
      if (heard.contains(t.id)) {
        if (knownOut.length < known) knownOut.add(t);
      } else if (freshOut.length < fresh) {
        freshOut.add(t);
      }
    }
  }
  // Alternati: un brano che conosci, uno nuovo.
  final out = <Track>[];
  for (var i = 0; i < knownOut.length || i < freshOut.length; i++) {
    if (i < knownOut.length) out.add(knownOut[i]);
    if (i < freshOut.length) out.add(freshOut[i]);
  }
  return out;
}

/// Gli artisti per i Daily Mix: i piu' ascoltati, ognuno coi suoi brani
/// piu' ascoltati (fino a [perArtist]). [plays] sono gli ascolti per
/// brano, [tracks] i brani conosciuti.
List<(String artist, List<Track> seeds)> mixArtists(
  Map<String, int> plays,
  Map<String, Track> tracks, {
  int artists = 4,
  int perArtist = 3,
}) {
  final byArtist = <String, List<String>>{};
  final artistPlays = <String, int>{};
  final names = <String, String>{};
  for (final e in plays.entries) {
    final t = tracks[e.key];
    if (t == null) continue;
    final name = mainArtist(t);
    final key = name.toLowerCase();
    names[key] = name;
    (byArtist[key] ??= []).add(e.key);
    artistPlays[key] = (artistPlays[key] ?? 0) + e.value;
  }
  final top = artistPlays.keys.toList()
    ..sort((a, b) => artistPlays[b]!.compareTo(artistPlays[a]!));
  return [
    for (final key in top.take(artists))
      (
        names[key]!,
        [
          for (final id
              in (byArtist[key]!
                    ..sort((a, b) => plays[b]!.compareTo(plays[a]!)))
                  .take(perArtist))
            tracks[id]!,
        ],
      ),
  ];
}

/// I colori dei Daily Mix, uno per mix, come le copertine numerate di
/// Spotify: si riconoscono a colpo d'occhio.
const dailyMixColors = [
  [Color(0xFFF59E0B), Color(0xFFEF4444)],
  [Color(0xFF10B981), Color(0xFF3B82F6)],
  [Color(0xFFA855F7), Color(0xFFEC4899)],
  [Color(0xFF84CC16), Color(0xFF14B8A6)],
];

/// Il lunedi' della settimana di [d]: Discover Weekly cambia allora.
String weekKey(DateTime d) {
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  return '${monday.year}-${monday.month}-${monday.day}';
}

String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
